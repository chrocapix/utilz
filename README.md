# utilz

A small collection of utilities for zig projects and a project creation tool.
Requires zig version 0.15.

## Usage

### Creating new projects with `init-zig.sh`

#### Step 1: Installation

0. clone the repository
1. checkout a tag matching your zig version (eg 0.15.1-0.3)
2. add the repository dir to your `$PATH`

#### Step 2: run the script

0. create an empty directory and `cd` into it
1. run `init-zig.sh`
2. done!

You now have a working CLI tool that showcases the utilz modules.

### Using the modules in an existing project

```
zig fetch --save https://github.com/chrocapix/utilz/archive/refs/tags/0.15.1-0.3.tar.gz
```

and in your `build.zig`:
```
    const exe = b.addExecutable(...);
    
    const utilz = b.dependency("utilz", .{
		.target = target,
		.optimize = optimize,
	});
    exe.root_module.addImport("utilz.argz", utilz.module("argz"));
    exe.root_module.addImport("utilz.timer", utilz.module("timer"));
```

Note that the `argz` and `juice` modules conflict with each other because `juice` imports `argz`.

## Details

### utilz.argz

A CLI parsing tool, inspired by [zig-clap](https://github.com/Hejsil/zig-clap) but simpler and less configurable.

You simply write the help message, `utilz.argz` parses it and gives you a struct with corresponding fields.
Any line begining with '-' or '<', ignoring initial spaces, adds a field to the result, according to the folowing rules.

If the line starts with `-`, it's an option. both short (`-h`) and long (`--help`) are supported, eg:

```
  -v, --verbose      increase verbosity level
  -a                 just a short option
      --bob          just a long option
```

These are flags, they count how many times they appear in the command line so their type is `usize`.
eg: `mycli -vvv` will set `argv.verbose` to 3.

Options can have parameters:
```
  -n, --number=<int>     number of things.
```
`argv.number` will have type `?isize`. When parsing all these are valid syntax:
```
-n42
-n=42
--number 42
--number=42
```


Lastly, you can add named positional arguments:
```
<float>    [x] initial coordinate 
```
`argv.x` will have type `?f64`.

Supported types and their zig equivalent are:

* `<int>` -> `isize`
* `<uint>` -> `usize`
* `uXX` and `iXX` same as zig
* `<float>` -> `f64`
* `fXX` same as zig
* `<str>` -> `[]const u8`


If you define a `--help` flag and it's passed to the program, the parser will print the usage string verbatim to stdout and call `std.process.exit(0)`.

Complete example:
```
const std = @import("std");
const Argz = @import("utilz.argz").Argz;

const usage =
    \\usage: toto [options] [arguments]
    \\
    \\options:
    \\  -h, --help      print this help and exit.
    \\
    \\arguments:
    \\  <int>          [answer]
    \\
;

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var argz = try Argz(usage, .{}).init(gpa);
    defer argz.deinit();
    const argv = argz.parse();

    std.debug.print("count = {}\n", .{argv.answer orelse 42});
}
```


### `utilz.juice`

An utility in the spirit of the [juicy main](https://github.com/ziglang/zig/issues/24510) proposal.

Consider the following:
```
const juice = @import("utilz.juice");

const usage = "<uint> [count]";

pub fn juicyMain(i: juice.Init(usage)) !void {
    try i.out.print("count = {}\n", .{i.argv.count orelse 0});
}

pub fn main() !void {
    return juice.main(usage, juicyMain);
}
```

`juice.main` will pass a value of type `Init(usage)` to your `juicyMain` containing:

* a pointer to an `ArenaAllocator` backed by the `page_allocator`
* a general purpose allocator (`DebugAllocator` in debug builds, `smp_allocator` otherwise)
* standard input as a buffered `Reader`
* standard output as a buffered `Writer`
* standard error as an unbuffered `Writer`
* the environment map
* a default random number generator, seeded with `42` in debug builds, properly seeded otherwise
* the result of `Argz(usage).parse`, see [argz](#utilz.argz) for details

Buffer sizes for stdin and stdout can be selected via the "IO_BUFSIZE" environment variable, defaulting to 1024 bytes.

Additionally, `juice.main` will flush stdout after your `juicyMain` returns so you *can* forget to flush. :)


Full definition of `Init` for reference:
```
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
```


### `utilz.timer`

A thin wrapper around `std.time.Timer` with subjectively better printing:

* Only prints times in nanoseconds, microseconds, milliseconds or seconds. No minutes, hours, etc.
* Always prints exactly 7 bytes, good for alignment when printing on several lines.
* prints as many significant digit as possible:
```
1.234ms
12.34ms
123.4ms
1.2345s
```
* `Timer.read()` returns a `Duration` object which has a `div` function:
```
    var tim = try Timer.start();
    for (0..n) |j| doStuff(j);
    const time = tim.read();
    std.log.info("doStuff: {f} total, {f}/call", .{ time, time.div(n) });
```
  
Limitation: due to the first two points, it can only print durations up to ~11.5 days (`999999s`).

### init-zig.sh

A zsh script that initializes a ready-to-go zig CLI project using the `utilz` modules. More precisely, it:

  0. runs `git init .` 
  1. populates it with `build.zig`, `build.zig.zon`, `.gitignore`, `src/main.zig`
  2. fetches `utilz` as a dependency
  3. `zig build` it
  4. `git add` and `git commit` the new files
