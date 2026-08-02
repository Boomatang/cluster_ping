const std = @import("std");

const Command = enum {
    check,
    validate,
    not_valid,
};

const Result = struct {
    help: bool,
    path: []const u8,
    name: []const u8,
    command: Command,
    delay: u32 = 300,

    // Pretty print function for debugging
    pub fn prettyPrint(self: *const Result) void {
        std.debug.print("Result {{\n", .{});
        std.debug.print("  help: {}\n", .{self.help});
        std.debug.print("  path: \"{s}\"\n", .{self.path});
        std.debug.print("  name: \"{s}\"\n", .{self.name});
        std.debug.print("  command: \"{any}\"\n", .{self.command});
        std.debug.print("  delay: \"{d}\"\n", .{self.delay});

        std.debug.print("}}\n", .{});
    }
};

const ProcessInfo = struct {
    pid: u32,
    name: []const u8,
    args: []const u8,

    // Pretty print function for debugging
    pub fn prettyPrint(self: *const ProcessInfo) void {
        std.debug.print("ProcessInfo {{\n", .{});
        std.debug.print("  pid: {}\n", .{self.pid});
        std.debug.print("  name: \"{s}\"\n", .{self.name});
        std.debug.print("  args: \"{s}\"\n", .{self.args});
        std.debug.print("}}\n", .{});
    }
};

const TimeResult = struct { connected: bool, timestamp: i64 };

const Cluster = struct {
    name: ?[]const u8 = null,
};

const SubContext = struct {
    cluster: ?[]const u8 = null,
    user: ?[]const u8 = null,
};

const Context = struct {
    context: ?SubContext = null,
    name: ?[]const u8 = null,
};

const SubUser = struct {
    @"client-certificate-data": ?[]const u8 = null,
    @"client-key-data": ?[]const u8 = null,
};

const User = struct {
    name: ?[]const u8 = null,
    user: ?SubUser = null,
};

const KubeConfig = struct {
    clusters: ?[]Cluster = null,
    contexts: ?[]Context = null,
    users: ?[]User = null,
};

const MyError = error{
    NotFound,
    NotImplemented,
    YqCommandFailed,
};

pub fn main(init: std.process.Init) !void {
    var buf: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &file_writer.interface;

    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const result = try parseArgs(args);

    if (result.help) {
        try print_help(stdout);
        std.process.exit(0);
    }

    switch (result.command) {
        Command.check => check_cluster_connection(init.io, allocator, result, init.environ_map) catch |err| switch (err) {
            else => {
                std.debug.print("We got this error, {}", .{err});
                return err;
            },
        },
        Command.validate => validate_connection(init.io, allocator, result, stdout) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        },
        else => try print_help(stdout),
    }
}

fn print_help(writer: *std.Io.Writer) !void {
    try writer.print("{s}\n", .{help_string()});
    try writer.flush(); // Don't forget to flush!
}

fn find_entry(io: std.Io, allocator: std.mem.Allocator, data: struct { path: []const u8, name: []const u8 }, file: std.Io.File) !?struct { connected: bool, timestamp: i64 } {
    var buf: [1024]u8 = undefined;
    var reader = file.reader(io, &buf);

    const key = try std.mem.concat(allocator, u8, &.{ data.path, data.name });
    defer allocator.free(key);

    while (reader.interface.takeDelimiter('\n') catch |err| switch (err) {
        error.ReadFailed => return if (reader.err) |e| e else error.ReadFailed,
        else => return err,
    }) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            const connected = line[key.len] != '0';
            const timestamp = try std.fmt.parseInt(i64, line[key.len + 1 ..], 10);
            return .{ .connected = connected, .timestamp = timestamp };
        }
    }
    return null;
}

fn validate_connection(io: std.Io, allocator: std.mem.Allocator, data: Result, writer: *std.Io.Writer) !void {
    const file = try std.Io.Dir.cwd().openFile(io, "/tmp/cluster_ping", .{ .mode = .read_only });
    defer file.close(io);
    const result = try find_entry(io, allocator, .{ .path = data.path, .name = data.name }, file);
    const delay = data.delay * 1000;

    if (result) |r| {
        const time_unit = r.timestamp + delay;
        const in_time = (std.Io.Timestamp.now(io, .real).toMilliseconds() < time_unit);
        try writer.print("connected={} recent={}\n", .{ r.connected, in_time });
        try writer.flush(); // Don't forget to flush!
    }
}

fn check_cluster_connection(io: std.Io, allocator: std.mem.Allocator, data: Result, environ_map: *std.process.Environ.Map) !void {
    try exit_if_running(io, allocator, data);
    const kube = read_kube_config(io, allocator, data) catch |err| switch (err) {
        MyError.NotFound => {
            std.debug.print("error 1: {}\n", .{err});
            return;
        },
        error.FileNotFound => {
            std.debug.print("error 1: {}\n", .{err});
            return;
        },
        else => return err,
    };
    defer kube.parsed.deinit();
    defer allocator.free(kube.json_data);

    const kube_config = kube.parsed.value;

    const user = get_user(kube_config, data.name) catch |err| switch (err) {
        MyError.NotFound => return,
        else => return err,
    };

    if (none_user(kube_config, user)) {
        std.debug.print("This was a none user\n", .{});
        return MyError.NotImplemented;
    }

    const connected = try can_connect(io, allocator, data.path, environ_map);

    try write_data(io, allocator, data, connected);
}

fn get_file(io: std.Io, path: []const u8) !std.Io.File {
    return std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write }) catch |err|
        switch (err) {
            error.FileNotFound => {
                return try std.Io.Dir.cwd().createFile(io, path, .{});
            },
            else => return err,
        };
}

fn write_data(io: std.Io, allocator: std.mem.Allocator, data: Result, connected: bool) !void {
    const tmp_dir = "/tmp/cluster_ping";
    const file = try get_file(io, tmp_dir);

    var read_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf).interface;
    const contents = file_reader.buffered();

    var split_contents = std.mem.splitSequence(u8, contents, "\n");
    const key = try std.mem.concat(allocator, u8, &.{ data.path, data.name });
    defer allocator.free(key);
    var next_data: std.ArrayList([]const u8) = .empty;
    defer next_data.deinit(allocator);

    const connected_u8: u8 = @intFromBool(connected);
    const time = std.Io.Timestamp.now(io, .real).toMilliseconds();

    var buf: [40]u8 = undefined;
    const connected_str = try std.fmt.bufPrint(&buf, "{}{}", .{ connected_u8, time });
    const value = try std.mem.concat(allocator, u8, &.{ key, connected_str });
    defer allocator.free(value);

    var not_found = true;
    while (split_contents.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            not_found = false;
            try next_data.append(allocator, value);
        } else {
            try next_data.append(allocator, line);
        }
    }
    if (not_found) {
        try next_data.append(allocator, value);
    }

    file.close(io);

    const write_file = try std.Io.Dir.cwd().createFile(io, tmp_dir, .{});
    defer write_file.close(io);

    var write_buf: [1024]u8 = undefined;
    var file_writer = write_file.writer(io, &write_buf);
    const writer = &file_writer.interface;
    for (next_data.items) |line| {
        if (line.len > 0) {
            try writer.print("{s}\n", .{line});
        }
    }
    try writer.flush();
}

// Mutates environ_map by setting KUBECONFIG — not safe to call with different paths in the same process.
fn can_connect(io: std.Io, allocator: std.mem.Allocator, path: []const u8, environ_map: *std.process.Environ.Map) !bool {
    const argv = [4][]const u8{ "kubectl", "version", "-o", "json" };

    try environ_map.put("KUBECONFIG", path);

    const home = environ_map.get("HOME") orelse return error.NoPath;

    const result = std.process.run(allocator, io, .{
        .argv = &argv,
        .cwd = std.process.Child.Cwd{ .path = home },
        .environ_map = environ_map,
    }) catch |err| {
        std.debug.print("Failed to run kubectl: {}\n", .{err});
        return err;
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.exited != 0) {
        return false;
    }

    return true;
}

fn none_user(kc: KubeConfig, user: []const u8) bool {
    if (kc.users) |users| {
        for (users) |u| {
            if (u.name) |name| {
                if (std.mem.eql(u8, name, user)) {
                    if (u.user == null) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

fn get_user(kc: KubeConfig, cluster: []const u8) ![]const u8 {
    var user: []const u8 = "";
    var c_cluster: []const u8 = "";
    if (kc.contexts) |contexts| {
        for (contexts) |context| {
            if (context.name) |name| {
                if (std.mem.eql(u8, name, cluster)) {
                    if (context.context) |c| {
                        if (c.cluster) |cluster_| {
                            if (cluster_.len == 0) {
                                return MyError.NotFound;
                            }
                            c_cluster = cluster_;
                        }
                        if (c.user) |u| {
                            user = u;
                        }
                        break;
                    }
                }
            }
        }
    }
    if (kc.clusters) |clusters| {
        for (clusters) |c| {
            if (c.name) |name| {
                if (std.mem.eql(u8, name, c_cluster)) {
                    return user;
                }
            }
        }
    }

    return MyError.NotFound;
}

fn commandToEnum(command: []const u8) Command {
    if (std.mem.eql(u8, command, "check")) return .check;
    if (std.mem.eql(u8, command, "validate")) return .validate;
    return .not_valid;
}

fn parseArgs(args: []const []const u8) !Result {
    var result = Result{ .help = true, .name = "", .path = "", .command = Command.not_valid };

    if (args.len == 1) {
        return result;
    }

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            return result;
        }
    }

    if (args.len >= 4) {
        result.help = false;
        result.path = args[2];
        result.name = args[3];
        result.command = commandToEnum(args[1]);
    }
    if (args.len == 5) {
        const num = try std.fmt.parseInt(u32, args[4], 10);
        result.delay = num;
    }

    return result;
}

test "help bool set if on args" {
    var more_sources: []const [:0]const u8 = &[_][:0]const u8{ "program", "--help" };
    var result = try parseArgs(more_sources);
    try std.testing.expectEqual(true, result.help);

    more_sources = &[_][:0]const u8{"program"};
    result = try parseArgs(more_sources);
    try std.testing.expectEqual(true, result.help);
}

test "Correct args for cluster ping have being set" {
    const more_sources: []const [:0]const u8 = &[_][:0]const u8{ "program", "check", "file path", "cluster name" };
    const result = try parseArgs(more_sources);
    try std.testing.expectEqual(false, result.help);
    try std.testing.expectEqual("file path", result.path);
    try std.testing.expectEqual("cluster name", result.name);
    try std.testing.expectEqual(Command.check, result.command);
}

test "Correct args for cluster validate have being set" {
    const more_sources: []const [:0]const u8 = &[_][:0]const u8{ "program", "validate", "file path", "cluster name" };
    const result = try parseArgs(more_sources);
    try std.testing.expectEqual(false, result.help);
    try std.testing.expectEqual("file path", result.path);
    try std.testing.expectEqual("cluster name", result.name);
    try std.testing.expectEqual(Command.validate, result.command);
}

fn help_string() []const u8 {
    return
    \\ usage: cluster_ping command kubeconfig cluster seconds
    \\
    \\ Check if current kube user can ping the current cluster
    \\ 
    \\ positional arguments:
    \\   command     which task to do check|validate
    \\   kubeconfig  path to kubeconfig file
    \\   cluster     name of cluster to ping
    \\   seconds     Time for valid check, default 300
    ;
}

fn exit_if_running(io: std.Io, allocator: std.mem.Allocator, result: Result) !void {
    const separator = " ";
    const total_len = result.path.len + result.name.len + separator.len;
    const data = try allocator.alloc(u8, total_len);
    defer allocator.free(data);

    @memcpy(data[0..result.path.len], result.path);
    @memcpy(data[result.path.len .. result.path.len + separator.len], separator);
    @memcpy(data[result.path.len + separator.len ..], result.name);

    const resp = try findProcessLinux(io, allocator, data);
    if (resp) |process_list| {
        var list = process_list;
        defer {
            for (list.items) |i| {
                allocator.free(i.name);
                allocator.free(i.args);
            }
            list.deinit(allocator);
        }
        if (list.items.len > 1) {
            std.process.exit(0);
        }
    }
}

fn findProcessLinux(io: std.Io, allocator: std.mem.Allocator, target_args: []const u8) !?std.ArrayList(ProcessInfo) {
    var proc_dir = try std.Io.Dir.openDirAbsolute(io, "/proc", .{ .iterate = true });
    defer proc_dir.close(io);

    var buf: [4096]u8 = undefined;

    var process_list: std.ArrayList(ProcessInfo) = .empty;

    var iter = proc_dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;

        // Check if directory name is numeric (PID)
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;

        // Read cmdline file
        const cmdline_path = try std.fmt.allocPrint(allocator, "/proc/{d}/cmdline", .{pid});
        defer allocator.free(cmdline_path);

        const cmdline_file = std.Io.Dir.openFileAbsolute(io, cmdline_path, .{}) catch continue;
        defer cmdline_file.close(io);

        var cmdline_file_reader = cmdline_file.reader(io, &buf).interface;
        const cmdline_data = cmdline_file_reader.buffered();
        defer allocator.free(cmdline_data);

        // Convert null-separated arguments to space-separated
        var args_list: std.ArrayList(u8) = .empty;
        defer args_list.deinit(allocator);

        for (cmdline_data, 0..) |byte, i| {
            if (byte == 0) {
                if (i < cmdline_data.len - 1) {
                    try args_list.append(allocator, ' ');
                }
            } else {
                try args_list.append(allocator, byte);
            }
        }

        const args_str = try args_list.toOwnedSlice(allocator);
        defer allocator.free(args_str);

        // Check if target arguments are contained in process arguments
        if (std.mem.indexOf(u8, args_str, target_args)) |_| {
            // Get process name from comm file
            const comm_path = try std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid});
            defer allocator.free(comm_path);

            const comm_file = std.Io.Dir.openFileAbsolute(io, comm_path, .{}) catch continue;
            defer comm_file.close(io);

            var comm_file_reader = comm_file.reader(io, &buf).interface;
            const comm_data = comm_file_reader.buffered();
            defer allocator.free(comm_data);

            // Remove trailing newline
            const name = if (comm_data.len > 0 and comm_data[comm_data.len - 1] == '\n')
                comm_data[0 .. comm_data.len - 1]
            else
                comm_data;

            const cp_name = try allocator.alloc(u8, name.len);
            const cp_args = try allocator.alloc(u8, args_str.len);
            @memcpy(cp_name, name);
            @memcpy(cp_args, args_str);

            try process_list.append(allocator, ProcessInfo{ .pid = pid, .name = cp_name, .args = cp_args });
        }
    }

    return process_list;
}

fn read_kube_config(io: std.Io, allocator: std.mem.Allocator, data: Result) !struct { parsed: std.json.Parsed(KubeConfig), json_data: []const u8 } {
    try std.Io.Dir.cwd().access(io, data.path, .{});

    const json_data = convertYamlToJson(io, allocator, data.path) catch |err| {
        std.debug.print("Failed to convert YAML to JSON: {}\n", .{err});
        return err;
    };
    errdefer allocator.free(json_data);

    const parsed = std.json.parseFromSlice(KubeConfig, allocator, json_data, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        std.json.ParseFromValueError.MissingField => return MyError.NotFound,
        else => return err,
    };
    return .{ .parsed = parsed, .json_data = json_data };
}

fn convertYamlToJson(io: std.Io, allocator: std.mem.Allocator, yaml_file_path: []const u8) ![]const u8 {
    const yq_args = [4][]const u8{ "yq", "eval", "-o=json", yaml_file_path };

    const result = std.process.run(allocator, io, .{
        .argv = &yq_args,
    }) catch |err| {
        std.debug.print("Failed to run yq: {}\n", .{err});
        return err;
    };

    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.exited != 0) {
        std.debug.print("yq command failed with exit code: {}\n", .{result.term.exited});
        std.debug.print("stderr: {s}\n", .{result.stderr});
        return MyError.YqCommandFailed;
    }
    return result.stdout;
}

test "Valid config used" {
    const config =
        \\{
        \\  "apiVersion": "v1",
        \\  "clusters": [
        \\    {
        \\      "cluster": {
        \\        "certificate-authority-data": "asdf",
        \\        "server": "https://127.0.0.1:43199"
        \\      },
        \\      "name": "kind-kind"
        \\    }
        \\  ],
        \\  "contexts": [
        \\    {
        \\      "context": {
        \\        "cluster": "kind-kind",
        \\        "user": "kind-kind"
        \\      },
        \\      "name": "kind-kind"
        \\    }
        \\  ],
        \\  "current-context": "kind-kind",
        \\  "kind": "Config",
        \\  "preferences": {},
        \\  "users": [
        \\    {
        \\      "name": "kind-kind",
        \\      "user": {
        \\        "client-certificate-data": "asdf",
        \\        "client-key-data": "asdf"
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const parsed = try std.json.parseFromSlice(KubeConfig, std.testing.allocator, config, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
}

test "more_missing_fields_testing" {
    const config =
        \\ {
        \\   "apiVersion": "v1",
        \\   "clusters": [
        \\     {
        \\       "cluster": {
        \\         "insecure-skip-tls-verify": true,
        \\         "server": "https://api.ci-ln-y9m1772-76ef8.aws-2.ci.openshift.org:6443"
        \\       },
        \\       "name": "api-ci-ln-y9m1772-76ef8-aws-2-ci-openshift-org:6443"
        \\     },
        \\     {
        \\       "cluster": {
        \\         "certificate-authority-data": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...short_cert_1",
        \\         "server": "https://127.0.0.1:37609"
        \\       },
        \\       "name": "kind-kuadrant-dns-local-1"
        \\     },
        \\     {
        \\       "cluster": {
        \\         "certificate-authority-data": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...short_cert_2",
        \\         "server": "https://127.0.0.1:39733"
        \\       },
        \\       "name": "kind-kind"
        \\     }
        \\   ],
        \\   "contexts": [
        \\     {
        \\       "context": {
        \\         "cluster": "api-ci-ln-y9m1772-76ef8-aws-2-ci-openshift-org:6443",
        \\         "namespace": "default",
        \\         "user": "kube:admin/api-ci-ln-y9m1772-76ef8-aws-2-ci-openshift-org:6443"
        \\       },
        \\       "name": "default/api-ci-ln-y9m1772-76ef8-aws-2-ci-openshift-org:6443/kube:admin"
        \\     },
        \\     {
        \\       "context": {
        \\         "cluster": "kind-kuadrant-dns-local-1",
        \\         "user": "kind-kuadrant-dns-local-1"
        \\       },
        \\       "name": "kind-kuadrant-dns-local-1"
        \\     },
        \\     {
        \\       "context": {
        \\         "cluster": "kind-kind",
        \\         "user": "kind-kind"
        \\       },
        \\       "name": "kind-kind"
        \\     }
        \\   ],
        \\   "current-context": "kind-kind",
        \\   "kind": "Config",
        \\   "preferences": {},
        \\   "users": [
        \\     {
        \\       "name": "kube:admin/api-ci-ln-y9m1772-76ef8-aws-2-ci-openshift-org:6443",
        \\       "user": {
        \\         "token": "sha256~7ZbrxBOxmTIBJweKwDWoOh5HldwDaSEuQrIHxX0wRZ8"
        \\       }
        \\     },
        \\     {
        \\       "name": "kind-kuadrant-dns-local-1",
        \\       "user": {
        \\         "client-certificate-data": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...short_client_cert_1",
        \\         "client-key-data": "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQ...short_client_key_1"
        \\       }
        \\     },
        \\     {
        \\       "name": "kind-kind",
        \\       "user": {
        \\         "client-certificate-data": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...short_client_cert_2",
        \\         "client-key-data": "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQ...short_client_key_2"
        \\       }
        \\     }
        \\   ]
        \\ }
    ;

    const parsed = std.json.parseFromSlice(KubeConfig, std.testing.allocator, config, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        std.json.ParseFromValueError.MissingField => {
            std.debug.print("Found the error, {any}\n", .{err});
            return err;
        },
        else => {
            std.debug.print("This was found {any}\n", .{err});
            return err;
        },
    };
    defer parsed.deinit();
}

test "Valid_empty_config_used" {
    const config =
        \\{
        \\  "apiVersion": "v1",
        \\  "kind": "Config",
        \\  "preferences": {}
        \\}
    ;

    const parsed = std.json.parseFromSlice(KubeConfig, std.testing.allocator, config, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        std.json.ParseFromValueError.MissingField => {
            std.debug.print("Found the error, {any}\n", .{err});
            return err;
        },
        else => {
            std.debug.print("This was found {any}\n", .{err});
            return err;
        },
    };
    defer parsed.deinit();
}
