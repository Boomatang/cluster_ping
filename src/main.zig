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

const Server = struct {
    @"certificate-authority-data": []const u8,
    server: []const u8,
};

const Cluster = struct {
    cluster: Server,
    name: []const u8,
};

const SubContext = struct {
    cluster: []const u8,
    user: []const u8,
};

const Context = struct {
    context: SubContext,
    name: []const u8,
};

const SubUser = struct {
    @"client-certificate-data": []const u8,
    @"client-key-data": []const u8,
};

const User = struct {
    name: []const u8,
    user: ?SubUser,
};

const KubeConfig = struct {
    apiVersion: []const u8,
    clusters: []Cluster,
    contexts: []Context,
    @"current-context": []const u8,
    kind: []const u8,
    users: []User,
    preferences: struct {},
};

pub const FileDataCluster = struct {
    name: []const u8,
    connected: bool,
    checked: i64,
};

pub const FileData = struct {
    clusters: []const FileDataCluster,
};

const MyError = error{
    NotFound,
    NotImplamented,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const result = try parseArgs(args);

    if (result.help) {
        try print_help();
    }

    switch (result.command) {
        Command.check => try check_cluster_connection(allocator, result),
        Command.validate => validate_connection(allocator, result) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        },
        else => try print_help(),
    }
}

fn print_help() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}\n", .{help_string()});

    try bw.flush(); // Don't forget to flush!
}

fn find_entry(allocator: std.mem.Allocator, data: struct { path: []const u8, name: []const u8 }, file: std.fs.File) !?struct { connected: bool, timestamp: i64 } {
    const endPos = try file.getEndPos();
    const contents = try allocator.alloc(u8, endPos);
    defer allocator.free(contents);
    _ = try file.readAll(contents);

    var split_contents = std.mem.splitSequence(u8, contents, "\n");
    const key = try std.mem.concat(allocator, u8, &.{ data.path, data.name });
    defer allocator.free(key);

    while (split_contents.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            const connected = line[key.len] != 0;
            const timestamp = try std.fmt.parseInt(i64, line[key.len + 1 ..], 10);
            return .{ .connected = connected, .timestamp = timestamp };
        }
    }
    return null;
}

fn validate_connection(allocator: std.mem.Allocator, data: Result) !void {
    const file = try std.fs.cwd().openFile("/tmp/cluster_ping", .{});
    defer file.close();
    const result = try find_entry(allocator, .{ .path = data.path, .name = data.name }, file);
    const delay = data.delay * 1000;
    const time_unit = result.?.timestamp + delay;
    const in_time = (std.time.milliTimestamp() < time_unit);
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("connected={} recent={}\n", .{ result.?.connected, in_time });

    try bw.flush(); // Don't forget to flush!
}

fn check_cluster_connection(allocator: std.mem.Allocator, data: Result) !void {
    try exit_if_running(allocator, data);
    const kube = read_kube_config(allocator, data) catch |err| switch (err) {
        error.FileNotFound => return,
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
        return MyError.NotImplamented;
    }

    const connected = try can_connect(allocator, data.path);

    try write_data(allocator, data, connected);
}

fn get_file(path: []const u8) !std.fs.File {
    return std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err|
        switch (err) {
            error.FileNotFound => {
                return try std.fs.cwd().createFile(path, .{});
            },
            else => return err,
        };
}

fn write_data(allocator: std.mem.Allocator, data: Result, connected: bool) !void {
    const tmp_dir = "/tmp/cluster_ping";
    const file = try get_file(tmp_dir);
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);
    var split_contents = std.mem.splitSequence(u8, contents, "\n");
    const key = try std.mem.concat(allocator, u8, &.{ data.path, data.name });
    defer allocator.free(key);
    var next_data = std.ArrayList([]const u8).init(allocator);
    defer next_data.deinit();

    const connected_u8: u8 = @intFromBool(connected);
    const time = std.time.milliTimestamp();
    var buf: [40]u8 = undefined;
    const connected_str = try std.fmt.bufPrint(&buf, "{}{}", .{ connected_u8, time });
    const value = try std.mem.concat(allocator, u8, &.{ key, connected_str });
    defer allocator.free(value);

    var not_found = true;
    while (split_contents.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            not_found = false;
            try next_data.append(value);
        } else {
            try next_data.append(line);
        }
    }
    if (not_found) {
        try next_data.append(value);
    }

    try file.seekTo(0);
    for (next_data.items) |line| {
        if (line.len > 0) {
            _ = try file.write(line);
            _ = try file.write("\n");
        }
    }
}

fn can_connect(allocator: std.mem.Allocator, path: []const u8) !bool {
    const argv = [4][]const u8{ "kubectl", "version", "-o", "json" };
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    try env_map.put("KUBECONFIG", path);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .cwd = null,
        .env_map = @constCast(&env_map),
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.debug.print("Failed to run kubectl: {}\n", .{err});
        return err;
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stderr.len > 0) {
        return false;
    }

    return true;
}

fn none_user(kc: KubeConfig, user: []const u8) bool {
    for (kc.users) |u| {
        if (std.mem.eql(u8, u.name, user)) {
            if (u.user == null) {
                return true;
            }
        }
    }
    return false;
}

fn get_user(kc: KubeConfig, cluster: []const u8) ![]const u8 {
    var user: []const u8 = "";
    var c_cluster: []const u8 = "";
    for (kc.contexts) |context| {
        if (std.mem.eql(u8, context.name, cluster)) {
            if (context.context.cluster.len == 0) {
                return MyError.NotFound;
            }
            c_cluster = context.context.cluster;
            user = context.context.user;
            break;
        }
    }
    for (kc.clusters) |c| {
        if (std.mem.eql(u8, c.name, c_cluster)) {
            return user;
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
    var result = parseArgs(more_sources);
    try std.testing.expectEqual(true, result.help);

    more_sources = &[_][:0]const u8{"program"};
    result = parseArgs(more_sources);
    try std.testing.expectEqual(true, result.help);

    more_sources = &[_][:0]const u8{ "program", "peter", "has", "tea" };
    result = parseArgs(more_sources);
    try std.testing.expectEqual(true, result.help);
}

test "Correct args have being set" {
    const more_sources: []const [:0]const u8 = &[_][:0]const u8{ "program", "file path", "cluster name" };
    const result = parseArgs(more_sources);
    try std.testing.expectEqual(false, result.help);
    try std.testing.expectEqual("file path", result.path);
    try std.testing.expectEqual("cluster name", result.name);
}

fn help_string() []const u8 {
    const str =
        \\ usage: cluster_ping command kubeconfig cluster seconds
        \\
        \\ Check if current kude user can ping the current cluster
        \\ 
        \\ positional arguments:
        \\   command     which task to do check|validate
        \\   kubeconfig  path to kubeconfig file
        \\   cluster     name of cluster to ping
        \\   seconds     Time for valid check, default 300
    ;

    return str;
}

fn exit_if_running(allocator: std.mem.Allocator, result: Result) !void {
    const seperator = " ";
    const total_len = result.path.len + result.name.len + seperator.len;
    const data = try allocator.alloc(u8, total_len);
    defer allocator.free(data);

    @memcpy(data[0..result.path.len], result.path);
    @memcpy(data[result.path.len .. result.path.len + seperator.len], seperator);
    @memcpy(data[result.path.len + seperator.len ..], result.name);
    // @memcpy(data[result.path.len + seperator.len ..], result.name);

    const resp = try findProcessLinux(allocator, data);
    if (resp) |process_list| {
        defer process_list.deinit();
        if (process_list.items.len > 1) {
            std.process.exit(0);
        }
    }
}

fn findProcessLinux(allocator: std.mem.Allocator, target_args: []const u8) !?std.ArrayList(ProcessInfo) {
    var proc_dir = try std.fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer proc_dir.close();

    var process_list = std.ArrayList(ProcessInfo).init(allocator);

    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Check if directory name is numeric (PID)
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;

        // Read cmdline file
        const cmdline_path = try std.fmt.allocPrint(allocator, "/proc/{d}/cmdline", .{pid});
        defer allocator.free(cmdline_path);

        const cmdline_file = std.fs.openFileAbsolute(cmdline_path, .{}) catch continue;
        defer cmdline_file.close();

        const cmdline_data = cmdline_file.readToEndAlloc(allocator, 4096) catch continue;
        defer allocator.free(cmdline_data);

        // Convert null-separated arguments to space-separated
        var args_list = std.ArrayList(u8).init(allocator);
        defer args_list.deinit();

        for (cmdline_data, 0..) |byte, i| {
            if (byte == 0) {
                if (i < cmdline_data.len - 1) {
                    try args_list.append(' ');
                }
            } else {
                try args_list.append(byte);
            }
        }

        const args_str = try args_list.toOwnedSlice();
        defer allocator.free(args_str);

        // Check if target arguments are contained in process arguments
        if (std.mem.indexOf(u8, args_str, target_args)) |_| {
            // Get process name from comm file
            const comm_path = try std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid});
            defer allocator.free(comm_path);

            const comm_file = std.fs.openFileAbsolute(comm_path, .{}) catch continue;
            defer comm_file.close();

            const comm_data = comm_file.readToEndAlloc(allocator, 256) catch continue;
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
            defer allocator.free(cp_name);
            defer allocator.free(cp_args);

            try process_list.append(ProcessInfo{ .pid = pid, .name = cp_name, .args = cp_args });
        }
    }

    return process_list;
}

fn read_kube_config(allocator: std.mem.Allocator, data: Result) !struct { parsed: std.json.Parsed(KubeConfig), json_data: []const u8 } {
    try std.fs.cwd().access(data.path, .{});

    const json_data = convertYamlToJson(allocator, data.path) catch |err| {
        std.debug.print("Failed to convert YAML to JSON: {}\n", .{err});
        return err;
    };

    const parsed = std.json.parseFromSlice(KubeConfig, allocator, json_data, .{}) catch |err| {
        allocator.free(json_data);
        return err;
    };
    return .{ .parsed = parsed, .json_data = json_data };
}

fn convertYamlToJson(allocator: std.mem.Allocator, yaml_file_path: []const u8) ![]const u8 {
    const yq_args = [4][]const u8{ "yq", "eval", "-o=json", yaml_file_path };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &yq_args,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.debug.print("Failed to run yq: {}\n", .{err});
        return err;
    };

    if (result.term.Exited != 0) {
        std.debug.print("yq command failed with exit code: {}\n", .{result.term.Exited});
        std.debug.print("stderr: {s}\n", .{result.stderr});
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        return error.YqCommandFailed;
    }
    allocator.free(result.stderr);
    return result.stdout;
}
