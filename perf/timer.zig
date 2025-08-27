const std = @import("std");
const builtin = @import("builtin");
const TimerOld = @import("timerold");
const Timer = @import("timer");
const juice = @import("juice");

const usage =
    \\options:
    \\  -h, --help          print this help and exit
    \\  -o, --out=<str>     output file (default: /dev/null)
    \\arguments:
    \\  <uint>  [n]
;

pub fn juicyMain(i: juice.Init(usage)) !void {
    try check(TimerOld, Timer);

    const out_name = i.argv.out orelse "/dev/null";

    var out_file = try OFile.open(i.gpa, out_name, .{});
    defer out_file.close();
    const out = out_file.writer();

    const n = i.argv.n orelse 42;

    try stdTimer(out, n);
    try baseline(out, n);
    try improved(out, n);
}

fn stdTimer(out: *std.Io.Writer, n: usize) !void {
    var stdTim = try std.time.Timer.start();
    var tim = try TimerOld.start();
    for (0..n) |_| {
        try out.print("{D}\n", .{stdTim.read()});
    }
    try out.flush();
    const time = tim.read();
    std.log.info("{f}, {f}/call: std.time.Timer", .{ time, time.div(n) });
}

fn baseline(out: *std.Io.Writer, n: usize) !void {
    var tim2 = try TimerOld.start();
    var tim = try TimerOld.start();
    for (0..n) |_| {
        try out.print("{f}\n", .{tim2.read()});
    }
    try out.flush();
    const time = tim.read();
    std.log.info("{f}, {f}/call: baseline", .{ time, time.div(n) });
}

fn improved(out: *std.Io.Writer, n: usize) !void {
    var tim2 = try Timer.start();
    var tim = try TimerOld.start();
    for (0..n) |_| {
        try out.print("{f}\n", .{tim2.read()});
    }
    try out.flush();
    const time = tim.read();
    std.log.info("{f}, {f}/call: improved", .{ time, time.div(n) });
}

fn check(T1: type, T2: type) !void {
    const D1 = T1.Duration;
    const D2 = T2.Duration;

    var buf1: [7]u8 = undefined;
    var buf2: [7]u8 = undefined;

    // _ = D1;
    // _ = D2;

    var d: u64 = 1;
    var ns: u64 = 1;
    while (ns < 10_000_000_0000_0000_000) {
        const d1: D1 = .init(ns);
        const d2: D2 = .init(ns);
        std.log.info("{f} {f} ns = {}", .{ d1, d2, ns });

        const r1 = try std.fmt.bufPrint(&buf1, "{f}", .{d1});
        const r2 = try std.fmt.bufPrint(&buf2, "{f}", .{d2});
        try std.testing.expect(std.mem.eql(u8, r1, r2));

        ns = ns * 10 + d;
        d += 1;
        if (d >= 5) d = 0;
    }
}

const OFile = struct {
    file: std.fs.File,
    gpa: std.mem.Allocator,
    buffer: []u8,
    file_writer: std.fs.File.Writer,

    pub fn open(
        gpa: std.mem.Allocator,
        name: []const u8,
        flags: std.fs.File.CreateFlags,
    ) !@This() {
        const file = try std.fs.cwd().createFile(name, flags);
        errdefer file.close();
        const buffer = try gpa.alloc(u8, 1024);
        return .{
            .file = file,
            .gpa = gpa,
            .buffer = buffer,
            .file_writer = file.writer(buffer),
        };
    }

    pub fn close(this: *@This()) void {
        this.file.close();
        this.gpa.free(this.buffer);
    }

    pub fn writer(this: *@This()) *std.Io.Writer {
        return &this.file_writer.interface;
    }
};

pub fn main() !void {
    return juice.main(usage, juicyMain);
}
