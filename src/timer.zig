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
    ns: f64,

    pub fn init(ns: u64) Duration {
        return .{ .ns = @floatFromInt(ns) };
    }

    pub fn div(this: @This(), count: anytype) Duration {
        const T = @TypeOf(count);
        const fcount: f64 =
            if (T == comptime_int)
                @floatCast(count)
            else if (T == comptime_float)
                @floatCast(count)
            else switch (@typeInfo(T)) {
                .int => @floatFromInt(count),
                .float => @floatCast(count),
                else => @compileError("Invalid type for Timer.Duration.div: " ++
                    @typeName(@TypeOf(count))),
            };
        return .{ .ns = this.ns / fcount };
    }

    pub fn format(this: @This(), w: *std.io.Writer) std.io.Writer.Error!void {
        const t = this.ns;
        std.debug.assert(t >= 0.0);

        var buf: [7]u8 = undefined;
        buf[6] = 's';

        if (t < 0.9995e3) {
            @branchHint(.likely);
            fmt10K(t, &buf);
            buf[5] = 'n';
            return w.writeAll(&buf);
        }

        if (t < 0.9995e6) {
            @branchHint(.likely);
            fmt10K(t * 1e-3, &buf);
            buf[5] = 'u';
            return w.writeAll(&buf);
        }

        if (t < 0.9995e9) {
            @branchHint(.likely);
            fmt10K(t * 1e-6, &buf);
            buf[5] = 'm';
            return w.writeAll(&buf);
        }

        if (t < 99999.5e9) {
            @branchHint(.likely);
            fmt100K(t * 1e-9, &buf);
            return w.writeAll(&buf);
        }

        if (t < 999999.5e9) {
            @branchHint(.likely);
            const n: i32 = @intFromFloat(t * 1e-9 + 0.5);
            std.debug.assert(n < 1_000_000);
            return w.print("{}s", .{n});
        }

        return w.writeAll("999999s");
    }

    fn fmt10K(x: f64, buf: []u8) void {
        const factor: [4]f64 = .{ 1000.0, 100.0, 10.0, 1.0 };
        const index =
            @as(u32, @intFromBool(x >= 9.9995)) +
            @as(u32, @intFromBool(x >= 99.995)) +
            @as(u32, @intFromBool(x >= 999.95));
        const n: u16 = @intFromFloat(x * factor[index] + 0.5);
        std.debug.assert(n >= 0);
        std.debug.assert(n < 10000);

        const zero = make64('0', '0', '0', '0', '0', '0');
        var pt = make64('.', '.', '.', '.', '.', '.');

        const d100 = n / 100;
        const r100 = n % 100;
        var lo = zero + make32(d100 / 10, d100 % 10, r100 / 10, r100 % 10);
        var hi = lo << 8;

        lo &= lo_mask[index];
        pt &= pt_mask[index];
        hi &= hi_mask[index];

        var txt = lo | pt | hi;
        // TODO: check that it's correct for big endian
        if (builtin.cpu.arch.endian() == .big)
            txt = std.mem.nativeToLittle(u64, txt);
        @memcpy(buf[0..5], std.mem.toBytes(txt)[0..5]);
    }

    fn fmt100K(x: f64, buf: []u8) void {
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

        lo &= lo_mask[index];
        pt &= pt_mask[index];
        hi &= hi_mask[index];

        var txt = lo | pt | hi;
        // TODO: check that it's correct for big endian
        if (builtin.cpu.arch.endian() == .big)
            txt = std.mem.nativeToLittle(u64, txt);
        @memcpy(buf[0..6], std.mem.toBytes(txt)[0..6]);
    }

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

    fn make32(a0: u16, a1: u16, a2: u16, a3: u16) u64 {
        var res: u64 = a3;
        res = (res << 8) | a2;
        res = (res << 8) | a1;
        res = (res << 8) | a0;
        return res;
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

const expect = std.testing.expect;

test "Timer.format" {
    const ns0: u64 = 54321;

    const data = &.{
        .{ "0.000ns", 1e9 },
        .{ "0.001ns", 1e8 },
        .{ "0.005ns", 1e7 },
        .{ "0.054ns", 1e6 },
        .{ "0.543ns", 1e5 },
        .{ "5.432ns", 1e4 },
        .{ "54.32ns", 1e3 },
        .{ "543.2ns", 1e2 },
        .{ "5.432us", 1e1 },
        .{ "54.32us", 1e0 },
        .{ "543.2us", 1e-1 },
        .{ "5.432ms", 1e-2 },
        .{ "54.32ms", 1e-3 },
        .{ "543.2ms", 1e-4 },
        .{ "5.4321s", 1e-5 },
        .{ "54.321s", 1e-6 },
        .{ "543.21s", 1e-7 },
        .{ "5432.1s", 1e-8 },
        .{ "54321.s", 1e-9 },
        .{ "543210s", 1e-10 },
        .{ "999999s", 1e-11 },
    };

    var buffer: [8]u8 = undefined;
    const d: Duration = .init(ns0);

    inline for (data) |datum| {
        const text = datum[0];
        const div = datum[1];
        const fmt = try std.fmt.bufPrint(&buffer, "{f}", .{d.div(div)});
        try expect(std.mem.eql(u8, text, fmt));
        // std.debug.print("{s} {s} {e:.0}\n", .{ text, fmt, div });
    }
    //
    // var t: f64 = 1e9;
    // while (t > 1e-11) : (t /= 10.0) {
    //     const d: Duration = .init(ns0);
    //     std.debug.print(".{{ \"{f}\", {e:.0} }},\n", .{ d.div(t), t });
    // }
}

test "Timer.format rounding, 4 digits" {
    const ns_lo = 11114999;
    const ns_hi = 11115001;

    const data = &.{
        .{ "1.111ns", "1.112ns", 1e7 },
        .{ "11.11ns", "11.12ns", 1e6 },
        .{ "111.1ns", "111.2ns", 1e5 },
        .{ "1.111us", "1.112us", 1e4 },
        .{ "11.11us", "11.12us", 1e3 },
        .{ "111.1us", "111.2us", 1e2 },
        .{ "1.111ms", "1.112ms", 1e1 },
        .{ "11.11ms", "11.12ms", 1e0 },
        .{ "111.1ms", "111.2ms", 1e-1 },
    };

    var buffer: [8]u8 = undefined;
    inline for (data) |datum| {
        const text_lo = datum[0];
        const text_hi = datum[1];
        const div = datum[2];

        const lo: Duration = .init(ns_lo);
        const fmt_lo = try std.fmt.bufPrint(&buffer, "{f}", .{lo.div(div)});
        try expect(std.mem.eql(u8, text_lo, fmt_lo));

        const hi: Duration = .init(ns_hi);
        const fmt_hi = try std.fmt.bufPrint(&buffer, "{f}", .{hi.div(div)});
        try expect(std.mem.eql(u8, text_hi, fmt_hi));
    }
    // var t: f64 = 1e7;
    // while (t > 1e-1) : (t /= 10.0) {
    //     const lo: Duration = .init(ns_lo);
    //     const hi: Duration = .init(ns_hi);
    //
    //     std.debug.print(
    //         ".{{ \"{f}\", \"{f}\", {e:.0} }},\n",
    //         .{ lo.div(t), hi.div(t), t },
    //     );
    // }
}

test "Timer.format rounding, 5 digits" {
    const ns_lo = 111114999;
    const ns_hi = 111115001;

    const data = &.{
        .{ "1.1111s", "1.1112s", 1e-1 },
        .{ "11.111s", "11.112s", 1e-2 },
        .{ "111.11s", "111.12s", 1e-3 },
        .{ "1111.1s", "1111.2s", 1e-4 },
        .{ "11111.s", "11112.s", 1e-5 },
    };

    var buffer: [8]u8 = undefined;
    inline for (data) |datum| {
        const text_lo = datum[0];
        const text_hi = datum[1];
        const div = datum[2];

        const lo: Duration = .init(ns_lo);
        const fmt_lo = try std.fmt.bufPrint(&buffer, "{f}", .{lo.div(div)});
        try expect(std.mem.eql(u8, text_lo, fmt_lo));

        const hi: Duration = .init(ns_hi);
        const fmt_hi = try std.fmt.bufPrint(&buffer, "{f}", .{hi.div(div)});
        try expect(std.mem.eql(u8, text_hi, fmt_hi));
    }

    // var t: f64 = 1e-1;
    // while (t > 1e-5) : (t /= 10.0) {
    //     const lo: Duration = .init(ns_lo);
    //     const hi: Duration = .init(ns_hi);
    //
    //     std.debug.print(
    //         ".{{ \"{f}\", \"{f}\", {e:.0} }},\n",
    //         .{ lo.div(t), hi.div(t), t },
    //     );
    // }
}

test "Timer.format rounding, 6 digits" {
    const ns_lo = 1111114999;
    const ns_hi = 1111115001;
    const div = 1e-5;

    var buffer: [8]u8 = undefined;

    const lo: Duration = .init(ns_lo);
    const fmt_lo = try std.fmt.bufPrint(&buffer, "{f}", .{lo.div(div)});
    try expect(std.mem.eql(u8, "111111s", fmt_lo));

    const hi: Duration = .init(ns_hi);
    const fmt_hi = try std.fmt.bufPrint(&buffer, "{f}", .{hi.div(div)});
    try expect(std.mem.eql(u8, "111112s", fmt_hi));
}
