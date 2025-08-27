#!/bin/zsh

set -e

if (( $# != 1 )) then
	echo >&2 "error: usage: init-zig dirname"
	exit 2
fi

exe="$(realpath $0)"
home=${exe%/*}
print $home
version="$(git -C $home describe --all)"

if [[ ${version%/*} != "tags" ]] then
	print >&2 "warning: using untagged utilz: $version"
fi

url=https://github.com/chrocapix/utilz/archive/refs/$version.tar.gz

# exit 0

dirname=$1
name=${dirname##*/}

mkdir $dirname
cd $dirname

git init .

zig init -m

zig fetch --save $url
echo "info: fetched 'utilz' from $url"

cat >.gitignore <<EOF
.zig-cache
zig-out
*.o
EOF
echo "info: generated '.gitignore'"

mkdir src
cat >src/main.zig <<EOF
const std = @import("std");
const juice = @import("utilz.juice");
const Timer = @import("utilz.timer");

const usage =
    \\\\usage: $name [options] [arguments]
    \\\\
    \\\\options:
    \\\\  -h, --help      print this help and exit.
    \\\\
    \\\\arguments:
    \\\\  <uint>          [count]
    \\\\
;

pub fn juicyMain(i: juice.Init(usage)) !void {
    try i.out.print("count = {}\\n", .{i.argv.count orelse 0});
}

pub fn main() !void {
    var tim = try Timer.start();
    defer std.log.info("{f}: main", .{tim.read()});
    return juice.main(usage, juicyMain);
}
EOF
echo "info: generated 'src/main.zig'"

cat >build.zig <<EOF
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "$name",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .root_source_file = b.path("src/main.zig"),
        }),
    });

    const utilz = b.dependency("utilz", .{
		.target = target,
		.optimize = opt,
	});
    exe.root_module.addImport("utilz.juice", utilz.module("juice"));
    exe.root_module.addImport("utilz.timer", utilz.module("timer"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);
}
EOF
echo "info: generated 'build.zig'"

zig build
echo "info: build successful"

git add .
git commit -m "init"

# $EDITOR src/main.zig
