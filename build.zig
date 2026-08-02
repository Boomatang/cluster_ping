const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "cluster_ping",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

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
}
