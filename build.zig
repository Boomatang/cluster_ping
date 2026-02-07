const std = @import("std");
const zon = @import("build.zig.zon");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "cluster_ping",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Change log configuration
    const changelog_cmd = b.addSystemCommand(&.{
        "towncrier",
        "build",
        "--draft",
        "--version",
        zon.version,
    });
    const changelog_step = b.step("changelog_draft", "Build changelog draft");
    changelog_step.dependOn(&changelog_cmd.step);

    const changelog_release_cmd = b.addSystemCommand(&.{
        "towncrier",
        "build",
        "--version",
        zon.version,
    });
    const changelog_release_step = b.step("changelog_release", "Build changelog draft");
    changelog_release_step.dependOn(&changelog_release_cmd.step);

    // Build release command
    const release_step = b.step("release", "Build release archives");
    const release_checks = ReleaseChecksStep.create(b);

    const release_targets = [_]ReleaseTarget{
        .{ .os_tag = .linux, .arch = .x86_64, .os_name = "linux", .arch_name = "amd64" },
        .{ .os_tag = .linux, .arch = .aarch64, .os_name = "linux", .arch_name = "arm64" },
        .{ .os_tag = .macos, .arch = .x86_64, .os_name = "darwin", .arch_name = "amd64" },
        .{ .os_tag = .macos, .arch = .aarch64, .os_name = "darwin", .arch_name = "arm64" },
    };

    for (release_targets) |release_target| {
        const resolved_target = b.resolveTargetQuery(.{
            .cpu_arch = release_target.arch,
            .os_tag = release_target.os_tag,
        });
        const release_exe = addReleaseExecutable(
            b,
            resolved_target,
            optimize,
        );

        const archive_name = b.fmt("{s}_{s}_{s}_{s}.tar.gz", .{
            @tagName(zon.name),
            zon.version,
            release_target.os_name,
            release_target.arch_name,
        });
        const dist_dir = "dist";
        const staging_dir = b.fmt("{s}/stage_{s}_{s}", .{
            dist_dir,
            release_target.os_name,
            release_target.arch_name,
        });

        const clean_staging = b.addRemoveDirTree(b.path(staging_dir));
        const make_staging = b.addSystemCommand(&.{ "mkdir", "-p", staging_dir });
        make_staging.step.dependOn(&clean_staging.step);

        const copy_bin = b.addSystemCommand(&.{"cp"});
        copy_bin.addFileArg(release_exe.getEmittedBin());
        copy_bin.addArg(staging_dir);

        const copy_docs = b.addSystemCommand(&.{
            "cp",
            "README.md",
            "CHANGELOG.md",
            staging_dir,
        });

        const tar_cmd = b.addSystemCommand(&.{
            "tar",
            "-czf",
            b.fmt("{s}/{s}", .{ dist_dir, archive_name }),
            "-C",
            staging_dir,
            ".",
        });

        const clean_after = b.addRemoveDirTree(b.path(staging_dir));

        copy_bin.step.dependOn(&release_exe.step);
        copy_bin.step.dependOn(&make_staging.step);
        copy_bin.step.dependOn(&release_checks.step);
        copy_docs.step.dependOn(&make_staging.step);
        copy_docs.step.dependOn(&release_checks.step);
        tar_cmd.step.dependOn(&make_staging.step);
        tar_cmd.step.dependOn(&copy_docs.step);
        tar_cmd.step.dependOn(&copy_bin.step);
        tar_cmd.step.dependOn(&release_checks.step);
        clean_after.step.dependOn(&tar_cmd.step);
        release_step.dependOn(&clean_after.step);
    }
}

const ReleaseTarget = struct {
    os_tag: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
    os_name: []const u8,
    arch_name: []const u8,
};

const ReleaseChecksStep = struct {
    step: std.Build.Step,
    version: []const u8,

    pub fn create(b: *std.Build) *ReleaseChecksStep {
        const checks = b.allocator.create(ReleaseChecksStep) catch @panic("OOM");
        checks.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "release_checks",
                .owner = b,
                .makeFn = make,
            }),
            .version = b.dupe(zon.version),
        };

        return checks;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const checks: *ReleaseChecksStep = @fieldParentPtr("step", step);

        var dir = try std.fs.cwd().openDir("changelog.d", .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.eql(u8, entry.name, ".gitkeep")) continue;
            return step.fail("changelog.d contains fragment: {s}", .{entry.name});
        }

        const changelog = std.fs.cwd().readFileAlloc(step.owner.allocator, "CHANGELOG.md", 1024 * 1024) catch |err| {
            return step.fail("failed to read CHANGELOG.md: {s}", .{@errorName(err)});
        };
        defer step.owner.allocator.free(changelog);
        if (std.mem.indexOf(u8, changelog, checks.version) == null) {
            return step.fail("CHANGELOG.md missing version {s}", .{checks.version});
        }
    }
};

fn addReleaseExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    _ = optimize;
    const release_optimize: std.builtin.OptimizeMode = .ReleaseSmall;
    const exe = b.addExecutable(.{
        .name = @tagName(zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = release_optimize,
        }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "name", @tagName(zon.name));

    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();

    return exe;
}
