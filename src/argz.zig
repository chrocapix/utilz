const EnumParseError = error{ParseError};

pub fn parseEnum(comptime T: type) fn ([]const u8) EnumParseError!T {
    return struct {
        fn parse(str: []const u8) EnumParseError!T {
            return std.meta.stringToEnum(T, str) orelse error.ParseError;
        }
    }.parse;
}

pub fn Argz(comptime usage: []const u8, parsers: anytype) type {
    return struct {
        pub const params = ParamParser.parse(usage);
        pub const Args = ArgsType();

        A: std.mem.Allocator,
        argv: [][:0]u8,
        own_argv: bool,
        ipos: usize = 0,
        extra_tab: [][:0]const u8,
        extra_end: usize = 0,

        pub fn init(A: std.mem.Allocator) !@This() {
            const argv = try std.process.argsAlloc(A);
            errdefer std.process.argsFree(A, argv);
            const extra_tab = try A.alloc([:0]const u8, argv.len);
            return .{
                .A = A,
                .argv = argv,
                .own_argv = true,
                .extra_tab = extra_tab,
            };
        }

        pub fn initArgv(A: std.mem.Allocator, argv: [][:0]u8) !@This() {
            const extra_tab = try A.alloc([:0]const u8, argv.len);
            return .{
                .A = A,
                .argv = argv,
                .own_argv = false,
                .extra_tab = extra_tab,
            };
        }

        pub fn deinit(this: @This()) void {
            this.A.free(this.extra_tab);
            if (this.own_argv)
                std.process.argsFree(this.A, this.argv);
        }

        pub fn parse(this: *@This()) Args {
            var result = std.mem.zeroes(Args);

            var used_value = false;
            var iter = ArgvIterator.init(this.argv);
            while (iter.next(used_value) != null) {
                used_value = this.parseOpt(&result, iter) catch |err|
                    switch (err) {
                        error.NameNotFound => fatal(
                            iter,
                            "no such option: --{s}",
                            .{iter.opt.?.name.name},
                        ),
                        error.CodeNotFound => fatal(
                            iter,
                            "no such option: -{c}",
                            .{iter.opt.?.code.code},
                        ),
                        error.ParseError => fatal(iter, "parse error", .{}),
                        error.MissingArgument => fatal(
                            iter,
                            "missing argument",
                            .{},
                        ),
                        error.IgnoredArgument => fatal(
                            iter,
                            "option does not take arguments",
                            .{},
                        ),
                    };
            }

            if (@hasField(Args, "help") and result.help > 0) {
                var out = std.fs.File.stdout().writer(&.{});
                out.interface.writeAll(usage) catch {};
                std.process.exit(0);
            }

            return result;
        }

        const Error = error{
            NameNotFound,
            CodeNotFound,
            ParseError,
            MissingArgument,
            IgnoredArgument,
        };

        fn parseOpt(
            this: *@This(),
            result: *Args,
            iter: ArgvIterator,
        ) Error!bool {
            switch (iter.opt.?) {
                .name => |name| {
                    inline for (params) |p| if (eql(p.name, name.name))
                        return handleOption(iter, p, result, name.value);
                    return error.NameNotFound;
                },
                .code => |code| {
                    inline for (params) |p| if (p.code[0] == code.code)
                        return handleOption(iter, p, result, code.value);
                    return error.CodeNotFound;
                },
                .pos => |pos| {
                    var i: usize = 0;
                    inline for (params) |p| if (p.is_pos) {
                        if (i == this.ipos) {
                            _ = try handle(iter, p, result, pos);
                            this.ipos += 1;
                            return false;
                        }
                        i += 1;
                    };

                    this.extra_tab[this.extra_end] = pos;
                    this.extra_end += 1;
                    return false;
                },
            }
        }

        fn handleOption(
            iter: ArgvIterator,
            comptime p: Param,
            result: *Args,
            value: ArgvIterator.Value,
        ) !bool {
            const used = try handle(iter, p, result, value.value);
            if (!used and value.is_forced)
                return error.IgnoredArgument;
            return used;
        }

        fn handle(
            iter: ArgvIterator,
            comptime p: Param,
            result: *Args,
            value: ?[]const u8,
        ) !bool {
            if (p.arity == 0) {
                @field(result.*, p.fullName()) += 1;
                return false;
            }
            if (value) |v| {
                @field(result.*, p.fullName()) = parseValue(
                    p.typename,
                    v,
                ) catch {
                    fatal(
                        iter,
                        "could not parse '{s}' for type <{s}>",
                        .{ v, p.typename },
                    );
                };
                return true;
            }
            return error.MissingArgument;
        }

        pub fn parseValue(
            comptime typename: []const u8,
            str: []const u8,
        ) !Value(typename) {
            if (@hasField(@TypeOf(parsers), typename))
                return @field(parsers, typename)(str);

            const T = DefaultValue(typename) catch unreachable;
            switch (@typeInfo(T)) {
                .int => return std.fmt.parseInt(T, str, 0),
                .float => return std.fmt.parseFloat(T, str),
                else => {},
            }
            if (T == []const u8) return str;

            @compileError("argz: internal error: no parser for <" ++
                typename ++
                ">");
        }

        fn fatal(
            iter: ArgvIterator,
            comptime fmt: []const u8,
            args: anytype,
        ) noreturn {
            fatalMessage(iter, fmt, args) catch {};
            std.process.exit(2);
        }

        fn fatalMessage(
            iter: ArgvIterator,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            var errw = std.fs.File.stderr().writer(&.{});
            const err = &errw.interface;
            try err.print("error: argv:{}: ", .{iter.i});
            try err.print(fmt, args);
            try err.print("\n  {s}\n", .{iter.argv[iter.i]});
        }

        fn Value(typename: []const u8) type {
            if (@hasField(@TypeOf(parsers), typename)) {
                const P = @TypeOf(@field(parsers, typename));
                const R = @typeInfo(P).@"fn".return_type.?;
                return @typeInfo(R).error_union.payload;
            }
            return DefaultValue(typename) catch
                @compileError("no parser for type <" ++ typename ++ ">");
        }

        fn DefaultValue(typename: []const u8) !type {
            const Types = .{
                .int = isize,
                .uint = usize,
                .float = f64,
                .str = []const u8,
            };
            if (@hasField(@TypeOf(Types), typename))
                return @field(Types, typename);
            if (typename.len < 2) return error.NotFound;
            const bits = try std.fmt.parseInt(u16, typename[1..], 10);
            if (startsWith(typename, "i"))
                return @Type(.{ .int = .{
                    .bits = bits,
                    .signedness = .signed,
                } });
            if (startsWith(typename, "u"))
                return @Type(.{ .int = .{
                    .bits = bits,
                    .signedness = .unsigned,
                } });
            if (startsWith(typename, "f"))
                return @Type(.{ .float = .{ .bits = bits } });
            return error.NotFound;
        }

        pub fn ArgsType() type {
            var fields: [params.len]std.builtin.Type.StructField = undefined;
            for (params, &fields) |p, *f| {
                const name = std.fmt.comptimePrint("{s}", .{p.fullName()});
                const RealType = Value(p.typename);
                const Type = if (p.arity == 0) RealType else ?RealType;
                f.* = .{
                    .name = name,
                    .type = Type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(Type),
                };
            }
            return @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        }
    };
}

const ArgvIterator = struct {
    const Value = struct {
        i: usize = 0,
        value: ?[]const u8,
        is_inline: bool,
        is_forced: bool,
        pub fn format(
            this: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            const i = if (this.is_inline) "I" else " ";
            const f = if (this.is_forced) "F" else " ";
            if (this.value) |v|
                try writer.print("value{{ {s}{s} '{s}' }}", .{ i, f, v })
            else
                try writer.print("value{{ {s}{s} (null) }}", .{ i, f });
        }
    };
    const Option3 = struct {
        i: usize = 0,
        typ: union(enum) { name: []const u8, code: [:0]const u8, pos },
        value: Value,
    };
    const Option = union(enum) {
        name: struct { name: []const u8, value: Value },
        code: struct { code: u8, value: Value },
        pos: [:0]const u8,

        pub fn format(
            this: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            switch (this) {
                .name => |name| try writer.print(
                    "Option{{ name '{s}' {} }}",
                    .{ name.name, name.value },
                ),
                .code => |code| try writer.print(
                    "Option{{ code '{c}' {} }}",
                    .{ code.code, code.value },
                ),
                .pos => |pos| try writer.print(
                    "Option{{ pos '{s}' }}",
                    .{pos},
                ),
            }
        }
    };

    argv: [][:0]u8,
    i: usize = 0,
    j: usize = 0,
    is_past_dash2: bool = false,
    opt: ?Option = null,

    pub fn init(argv: [][:0]u8) @This() {
        return .{ .argv = argv };
    }

    pub fn next(this: *@This(), used_value: bool) ?Option {
        const r = this.doNext(used_value);
        // std.debug.print(
        //     "iter on argv[{}][{}]: used {} {any}\n",
        //     .{ this.i, this.j, used_value, r },
        // );
        this.opt = r;
        return r;
    }
    pub fn doNext(this: *@This(), used_value: bool) ?Option {
        if (this.j > 0) {
            if (used_value) {
                this.i += @intFromBool(!this.isInline());
                return this.nextArg();
            }
            return this.nextCode();
        }

        this.i += @intFromBool(used_value and !this.isInline());
        return this.nextArg();
    }

    pub fn isInline(this: @This()) bool {
        return if (this.opt) |opt| switch (opt) {
            .name => |name| name.value.is_inline,
            .code => |code| code.value.is_inline,
            .pos => false,
        } else false;
    }

    fn nextCode(this: *@This()) ?Option {
        const curr = this.argv[this.i];
        const after = if (this.i + 1 < this.argv.len)
            this.argv[this.i + 1]
        else
            null;

        this.j += 1;
        if (this.j >= curr.len) return this.nextArg();

        return if (this.j + 1 >= curr.len)
            .{ .code = .{ .code = curr[this.j], .value = .{
                .value = after,
                .is_inline = false,
                .is_forced = false,
            } } }
        else if (curr[this.j + 1] == '=')
            .{ .code = .{ .code = curr[this.j], .value = .{
                .value = curr[this.j + 2 ..],
                .is_inline = true,
                .is_forced = true,
            } } }
        else
            .{ .code = .{ .code = curr[this.j], .value = .{
                .value = curr[this.j + 1 ..],
                .is_inline = true,
                .is_forced = false,
            } } };
    }

    fn nextArg(this: *@This()) ?Option {
        this.i += 1;
        this.j = 0;
        if (this.i >= this.argv.len) return null;

        const curr = this.argv[this.i];
        const after = if (this.i + 1 < this.argv.len)
            this.argv[this.i + 1]
        else
            null;

        if (this.is_past_dash2) return .{ .pos = curr };

        if (eql(curr, "--")) {
            this.is_past_dash2 = true;
            return this.nextArg();
        }

        if (startsWith(curr, "--"))
            return if (indexOfScalar(curr, '=')) |ieq|
                .{ .name = .{ .name = curr[2..ieq], .value = .{
                    .value = curr[ieq + 1 ..],
                    .is_inline = true,
                    .is_forced = true,
                } } }
            else
                .{ .name = .{ .name = curr[2..], .value = .{
                    .value = after,
                    .is_inline = false,
                    .is_forced = false,
                } } };

        if (curr.len == 0 or curr[0] != '-' or
            curr.len == 1 or !isCode(curr[1]))
            return .{ .pos = curr };

        return this.nextCode();
    }
};

const Param = struct {
    code: []const u8,
    name: []const u8,
    is_pos: bool,
    typename: []const u8,
    arity: u1,

    // TODO: remove
    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        return writer.print(
            "Param{{ .code '{s}' .name '{s}', {s}, .type '{s}', .arity {}}}",
            .{
                this.code,
                this.name,
                if (this.is_pos) "pos" else "___",
                this.typename,
                this.arity,
            },
        );
    }

    pub fn fullName(comptime this: Param) []const u8 {
        return if (this.name.len == 0) this.code else this.name;
    }
};

const ParamParser = struct {
    pub fn parse(spec: []const u8) [count(spec)]Param {
        var tab: [count(spec)]Param = undefined;
        var parser: ParamParser = .{ .spec = spec };
        var j: usize = 0;
        for (0..spec.len) |i| if (isBegin(spec, i)) {
            parser.i = i;
            tab[j] = parser.parseParam();
            j += 1;
        };
        return tab;
    }

    pub fn count(spec: []const u8) usize {
        @setEvalBranchQuota(1_000_000);
        var len: usize = 0;
        for (0..spec.len) |i| len += @intFromBool(isBegin(spec, i));
        return len;
    }

    fn isBegin(spec: []const u8, i: usize) bool {
        const is_line_begin = i == 0 or spec[i - 1] == '\n';

        const trimmed = std.mem.trimLeft(u8, spec[i..], spaces);
        const is_param_begin =
            startsWith(trimmed, "-") or
            startsWith(trimmed, "<");

        return is_line_begin and is_param_begin;
    }

    spec: []const u8,
    i0: usize = 0,
    i: usize = 0,

    fn parseParam(this: *@This()) Param {
        var param: Param = .{
            .code = "\x00",
            .name = "",
            .typename = "uint",
            .arity = 0,
            .is_pos = false,
        };
        this.i0 = this.i;

        this.skipSpaces();

        if (this.tryParseType()) |typename| {
            param.typename = typename;
            param.is_pos = true;
            param.arity = 1;
            this.skipSpaces();
            _ = this.parseS("[");
            param.name = this.parseWord();
            _ = this.parseS("]");
            return param;
        }

        if (this.tryParseS("--") != null) {
            param.name = this.parseWord();
        } else {
            _ = this.parseS("-");
            param.code = this.parseCode();

            this.skipSpaces();
            if (this.tryParseS(",") != null) {
                this.skipSpaces();

                _ = this.parseS("--");
                param.name = this.parseWord();
            }
        }

        if (this.tryParseS("=") != null) {
            param.typename = this.parseType();
            param.arity = 1;
        }

        return param;
    }

    fn parseType(this: *@This()) []const u8 {
        if (this.tryParseType()) |name|
            return name;
        this.fatal("expected type", .{});
    }

    fn tryParseType(this: *@This()) ?[]const u8 {
        this.i0 = this.i;
        if (this.tryParseS("<") != null) {
            const name = this.parseWord();
            _ = this.parseS(">");
            return name;
        }
        return null;
    }

    fn parseCode(this: *@This()) []const u8 {
        this.i0 = this.i;
        if (this.i < this.spec.len and isCode(this.spec[this.i])) {
            this.i += 1;
            return this.spec[this.i0..this.i];
        }
        this.fatal("expected code");
    }

    fn parseWord(this: *@This()) []const u8 {
        this.i0 = this.i;
        if (this.i0 < this.spec.len and isWordBegin(this.spec[this.i0])) {
            this.i += 1;
        } else this.fatal("expected word", .{});

        while (this.i < this.spec.len and isWord(this.spec[this.i]))
            this.i += 1;
        return this.spec[this.i0..this.i];
    }

    fn parseS(this: *@This(), str: []const u8) []const u8 {
        return if (this.tryParseS(str)) |val|
            val
        else
            this.fatal("expected '{s}'", .{str});
    }

    fn tryParseS(this: *@This(), str: []const u8) ?[]const u8 {
        this.i0 = this.i;
        if (startsWith(this.spec[this.i..], str)) {
            this.i += str.len;
            return this.spec[this.i0..this.i];
        }
        return null;
    }

    fn skipSpaces(this: *@This()) void {
        this.i = std.mem.indexOfNonePos(u8, this.spec, this.i, spaces) orelse
            this.spec.len;
    }

    fn fatal(this: @This(), comptime fmt: []const u8, args: anytype) noreturn {
        const loc = std.zig.findLineColumn(this.spec, this.i0);
        if (@inComptime()) {
            const fmted = std.fmt.comptimePrint(fmt, args);
            const msg = std.fmt.comptimePrint(
                "argz:{}:{}: {s}\n{s}",
                .{ loc.line, loc.column, fmted, loc.source_line },
            );
            @compileError(msg);
        } else {}
    }

    const spaces = " \t";
};

fn isCode(char: u8) bool {
    return switch (char) {
        'A'...'Z', 'a'...'z', '_' => true,
        else => false,
    };
}

fn isWordBegin(char: u8) bool {
    return isCode(char) or char == '-';
}

fn isWord(char: u8) bool {
    return isWordBegin(char) or switch (char) {
        '0'...'9' => true,
        else => false,
    };
}

fn indexOfScalar(a: []const u8, b: u8) ?usize {
    return std.mem.indexOfScalar(u8, a, b);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn startsWith(a: []const u8, b: []const u8) bool {
    return std.mem.startsWith(u8, a, b);
}

const std = @import("std");

test "empty" {
    const a = std.testing.allocator;
    var argv0 = [_]u8{ 'p', 'o', 0 };
    var argv = [_][:0]u8{argv0[0..2 :0]};

    const expected =
        \\
    ;
    var argz = try Argz("", .{}).initArgv(a, &argv);
    defer argz.deinit();

    const actual = try allocFmtArgv(a, argz.parse());
    defer a.free(actual);
    // printMultiLine(actual);
    try expectEql(expected, actual);
}

test "int" {
    const a = std.testing.allocator;
    var argv0 = [_]u8{ 'p', 'o', 0 };
    var argv1 = [_]u8{ '4', '2', 0 };
    var argv = [_][:0]u8{ argv0[0..2 :0], argv1[0..2 :0] };

    const expected =
        \\int: ?isize = 42
        \\
    ;
    var argz = try Argz("<int> [int]", .{}).initArgv(a, &argv);
    defer argz.deinit();

    const actual = try allocFmtArgv(a, argz.parse());
    defer a.free(actual);
    // printMultiLine(actual);
    try expectEql(expected, actual);
}

fn expectEql(expected: []const u8, actual: []const u8) !void {
    return std.testing.expect(std.mem.eql(u8, expected, actual));
}

fn printMultiLine(text: []const u8) void {
    std.debug.print("const expected = \n", .{});
    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |line| {
        std.debug.print("\\\\{s}\n", .{line});
    }
    std.debug.print(";\n", .{});
}

fn allocFmtArgv(a: std.mem.Allocator, argv: anytype) ![]const u8 {
    var alloc: std.Io.Writer.Allocating = .init(a);
    defer alloc.deinit();
    const out = &alloc.writer;

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

    return alloc.toOwnedSlice();
}
