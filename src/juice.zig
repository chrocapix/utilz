const std = @import("std");
const builtin = @import("builtin");
pub const argz = @import("argz.zig");
const eql = std.mem.eql;
const starts = std.mem.startsWith;
const indexOf = std.mem.indexOfScalar;
const Type = std.builtin.Type;


pub fn Init(comptime usage: []const u8) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        gpa: std.mem.Allocator,

        in: *std.Io.Reader,
        out: *std.Io.Writer,
        err: *std.Io.Writer,

        env: std.process.EnvMap,

        rng: std.Random,

        argv: argz.Argz(usage, .{}).ArgsType(),
    };
}

pub fn main(
    comptime usage: []const u8,
    userMain: fn (Init(usage)) anyerror!void,
) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const ara = arena.allocator();

    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer {
        if (builtin.mode == .Debug) _ = dba.deinit();
    }
    const gpa = if (builtin.mode == .Debug)
        dba.allocator()
    else
        std.heap.smp_allocator;

    const env = try std.process.getEnvMap(ara);

    const default_bufsize = 1024;
    const bufsize = if (env.get("IO_BUFSIZE")) |text|
        std.fmt.parseIntSizeSuffix(text, 0) catch default_bufsize
    else
        default_bufsize;

    const in_buffer = try ara.alloc(u8, bufsize);
    var in_writer = std.fs.File.stdin().reader(in_buffer);

    const out_buffer = try ara.alloc(u8, bufsize);
    var out_writer = std.fs.File.stdout().writer(out_buffer);
    defer out_writer.interface.flush() catch
        std.log.err("flush failed", .{});

    var err_writer = std.fs.File.stderr().writer(&.{});

    var seed: u64 = 42;
    if (builtin.mode != .Debug)
        try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);

    var args: argz.Argz(usage, .{}) = try .init(ara);

    return userMain(.{
        .arena = &arena,
        .gpa = gpa,
        .in = &in_writer.interface,
        .out = &out_writer.interface,
        .err = &err_writer.interface,
        .env = env,
        .rng = prng.random(),
        .argv = args.parse(),
    });
}
