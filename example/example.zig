const std = @import("std");
const juice = @import("juice");
const Argz = juice.argz.Argz;
// const Argz = @import("argz").Argz;
const Timer = @import("timer");

pub fn main() !void {
    var tim: Timer = try .start();
    defer std.log.info("main: {f}", .{tim.read()});
    // return mainArgz();
    return mainJuice();
}

const usage =
    \\usage:
    \\  example [options] [arguments]
    \\
    \\options:
    \\  -h, --help           print this help and exit
    \\  -a, --alice=<int>
    \\  -b=<f128>
    \\  --charlie
    \\  --printbufsize      print the stdio buffer size
    \\   
    \\arguments:
    \\  <str>                [damien]
    \\
;

pub fn mainJuice() !void {
    return juice.main(usage, myMain);
}

pub fn myMain(i: juice.Init(usage)) !void {
    if (i.argv.printbufsize > 0)
        try i.out.print("bufsize = {Bi}\n", .{i.out.buffer.len});

    try printArgs(i.out, i.argv);

    if (i.argv.b) |b|
        try i.out.print("b = {e}\n", .{b});
}

pub fn mainArgz() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer _ = dba.deinit();
    const gpa = dba.allocator();

    var out_buf: [1024]u8 = undefined;
    var out_w = std.fs.File.stdout().writer(&out_buf);
    const out = &out_w.interface;
    defer out.flush() catch std.log.err("flush failed", .{});

    var argz = try Argz(usage, .{}).init(gpa);
    defer argz.deinit();
    const argv = argz.parse();

    try printArgs(out, argv);
}

fn printArgs(out: *std.io.Writer, argv: anytype) !void {
    inline for (@typeInfo(@TypeOf(argv)).@"struct".fields) |field| {
        try out.print("{s}: {s} = ", .{ field.name, @typeName(field.type) });
        const ti = @typeInfo(field.type);
        const value = @field(argv, field.name);
        switch (ti) {
            .optional => |o| switch (o.child) {
                []const u8 => if (value) |v|
                    try out.print("'{s}'", .{v})
                else
                    try out.print("(null)", .{}),
                else => if (value) |v|
                    try out.print("{}", .{v})
                else
                    try out.print("(null)", .{}),
            },
            .int => try out.print("{}", .{value}),
            else => try out.print("wat", .{}),
        }
        try out.print("\n", .{});
    }
}
