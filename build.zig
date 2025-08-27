const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const argz = b.addModule("argz", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/argz.zig"),
    });
    const timer = b.addModule("timer", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/timer.zig"),
    });
    const timerold = b.addModule("timerold", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/timerold.zig"),
    });
    const juice = b.addModule("juice", .{
        .target = target,
        .optimize = opt,
        .root_source_file = b.path("src/juice.zig"),
    });

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("example/example.zig"),
        }),
    });
    _ = argz;
    _ = example;

    const perf = b.addExecutable(.{
        .name = "perf-timer",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("perf/timer.zig"),
        }),
    });
    perf.root_module.addImport("timer", timer);
    perf.root_module.addImport("timerold", timerold);
    perf.root_module.addImport("juice", juice);

    const installAssembly = b.addInstallBinFile(perf.getEmittedAsm(), "perf.s");
    b.getInstallStep().dependOn(&installAssembly.step);

    const run_exe = b.addRunArtifact(perf);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the perf tool");
    run_step.dependOn(&run_exe.step);
}
