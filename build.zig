const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("example/example.zig"),
        }),
    });

    inline for (.{ "argz", "timer", "juice" }) |name| {
        const mod = b.addModule(name, .{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
        });

        example.root_module.addImport(name, mod);
    }

    const run_exe = b.addRunArtifact(example);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_exe.step);
}
