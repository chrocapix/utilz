# utilz

A small collection of utilities for zig projects.

It exposes three modules and a shell script.

## `utilz.argz`

A CLI parsing tool, inspired by [zig-clap](https://github.com/Hejsil/zig-clap) but simpler and less configurable.

## `utilz.juice`

An utility in the spirit of the [juicy main](https://github.com/ziglang/zig/issues/24510) proposal.

## `utilz.timer`

A thin wrapper around `std.time.Timer` with subjectively better printing.

## init-zig.sh

A zsh script that creates a ready-to-go zig CLI project using `utilz`. More precisely, it:

  0. `git init` it
  1. populates it with `build.zig`, `build.zig.zon`, `.gitignore`, `src/main.zig`
  2. fetches `utilz` as a dependency
  3. `zig build` it
  4. `git add` and `git commit` the new files
  5. run `$EDITOR` on `src/main.zig`
