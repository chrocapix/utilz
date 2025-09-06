const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});
    const install_example =
        b.option(bool, "example", "install the example") orelse false;

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("example/example.zig"),
        }),
    });

    const check = b.step("check", "");
    check.dependOn(&example.step);

    const argz_mod = b.addModule("argz", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/argz.zig"),
    });
    example.root_module.addImport("argz", argz_mod);

    const juice_mod = b.addModule("juice", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/juice.zig"),
    });
    example.root_module.addImport("juice", juice_mod);

    const timer_mod = b.addModule("timer", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/timer.zig"),
    });
    example.root_module.addImport("timer", timer_mod);

    if (install_example) {
        b.installArtifact(example);
    }

    const test_step = b.step("test", "Run unit tests");
    const timer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/timer.zig"),
            .target = target,
            .optimize = opt,
        }),
        .name = "timer test",
    });
    const run_timer_test = b.addRunArtifact(timer_test);
    test_step.dependOn(&run_timer_test.step);
    const argz_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/argz.zig"),
            .target = target,
            .optimize = opt,
        }),
        .name = "argz test",
    });
    const run_argz_test = b.addRunArtifact(argz_test);
    test_step.dependOn(&run_argz_test.step);

    const run_exe = b.addRunArtifact(example);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_exe.step);
}
