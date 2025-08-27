const std = @import("std");
const builtin = @import("builtin");

tim: std.time.Timer,

pub fn start() !@This() {
    return .{ .tim = try std.time.Timer.start() };
}

pub fn read(this: *@This()) Duration {
    return .init(this.tim.read());
}

pub fn lap(this: *@This()) Duration {
    return .init(this.tim.lap());
}

pub fn reset(this: *@This()) void {
    this.tim.reset();
}

pub const Duration = struct {
    seconds: f64,

    pub fn init(ns: u64) Duration {
        return .{ .seconds = 1e-9 * @as(f64, @floatFromInt(ns)) };
    }

    pub fn div(this: @This(), count: anytype) Duration {
        const fcount: f64 =
            switch (@typeInfo(@TypeOf(count))) {
                .int => @floatFromInt(count),
                .float => @floatCast(count),
                else => @compileError("Invalid type for Timer.Duration.div: " ++ @typeName(@TypeOf(count))),
            };
        return .{ .seconds = this.seconds / fcount };
    }

    pub fn format(this: @This(), w: *std.io.Writer) std.io.Writer.Error!void {
        const t = this.seconds;

        var buf: [8]u8 = undefined;

        if (t < 0) {
            @branchHint(.unlikely);
            return w.writeAll("-XX.XXs");
        }

        if (t < 0.9995) {
            @branchHint(.likely);
            const scale: [3]f64 = .{ 1e9, 1e6, 1e3 };
            const si: [3]u8 = .{ 'n', 'u', 'm' };
            const index =
                @as(u32, @intFromBool(t >= 0.9995e-6)) +
                @as(u32, @intFromBool(t >= 0.9995e-3));

            fmt100K(t * scale[index], &buf);
            buf[5] = si[index];
            buf[6] = 's';
            return w.writeAll(buf[0..7]);
        }

        if (t < 99999.5) {
            fmt100K(t, &buf);
            buf[6] = 's';
            return w.writeAll(buf[0..7]);
        }
        if (t < 999999.5) {
            const n: i32 = @intFromFloat(t + 0.5);
            return w.print("{}s", .{n});
        }
        return w.writeAll("999999s");
    }

    pub fn fmt100K(x: f64, buf: []u8) void {
        const factor: [5]f64 = .{ 10000.0, 1000.0, 100.0, 10.0, 1.0 };
        const index =
            @as(u32, @intFromBool(x >= 9.9995)) +
            @as(u32, @intFromBool(x >= 99.995)) +
            @as(u32, @intFromBool(x >= 999.95)) +
            @as(u32, @intFromBool(x >= 9999.5));
        const n: i32 = @intFromFloat(x * factor[index] + 0.5);
        std.debug.assert(n >= 0);
        std.debug.assert(n < 100000);

        const zero = make64('0', '0', '0', '0', '0', '0');
        var pt = make64('.', '.', '.', '.', '.', '.');
        var lo = zero + make64(
            @divTrunc(n, 10000),
            @rem(@divTrunc(n, 1000), 10),
            @rem(@divTrunc(n, 100), 10),
            @rem(@divTrunc(n, 10), 10),
            @rem(n, 10),
            0,
        );
        var hi = lo << 8;

        const lo_mask: [5]u64 = .{
            0x000000000000ff,
            0x0000000000ffff,
            0x00000000ffffff,
            0x000000ffffffff,
            0x0000ffffffffff,
        };
        const pt_mask: [5]u64 = .{
            0x0000000000ff00,
            0x00000000ff0000,
            0x000000ff000000,
            0x0000ff00000000,
            0x00ff0000000000,
        };
        const hi_mask: [5]u64 = .{
            0xffffffff0000,
            0xffffff000000,
            0xffff00000000,
            0xff0000000000,
            0x000000000000,
        };

        lo &= lo_mask[index];
        pt &= pt_mask[index];
        hi &= hi_mask[index];

        var txt = lo | pt | hi;
        if (builtin.cpu.arch.endian() == .big)
            txt = std.mem.nativeToLittle(u64, txt);
        @memcpy(buf[0..6], std.mem.toBytes(txt)[0..6]);
    }

    fn make64(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32) u64 {
        return @as(u64, @intCast(a0)) |
            (@as(u64, @intCast(a1)) << 8) |
            (@as(u64, @intCast(a2)) << 16) |
            (@as(u64, @intCast(a3)) << 24) |
            (@as(u64, @intCast(a4)) << 32) |
            (@as(u64, @intCast(a5)) << 40);
    }
};
