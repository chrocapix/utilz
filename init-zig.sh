#!/bin/zsh

set -e

if (( $# != 1 )) then
	echo >&2 "error: usage: init-zig dirname"
	exit 2
fi

dirname=$1

if [[ -e $dirname ]] then
	print >&2 "error: file exists: '$dirname'"
	exit 2
fi

name=${dirname##*/}
exe="$(realpath $0)"
home=${exe%/*}
version="$(git -C $home describe --all)"
print "info: using utilz in '$home' version $version"


if [[ ${version%/*} != "tags" ]] then
	print >&2 "warning: using untagged utilz: $version"
fi

mkdir -vp $dirname
cd $dirname
git init .
zig init -m

url=https://github.com/chrocapix/utilz/archive/refs/$version.tar.gz
zig fetch --save $url
print "info: fetched '$url'"

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
    \\\\  <uint>          [answer]
    \\\\
;

pub fn juicyMain(i: juice.Init(usage)) !void {
    try i.out.print("answer = {}\\n", .{i.argv.answer orelse 42});
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
echo "info: commit successful"
