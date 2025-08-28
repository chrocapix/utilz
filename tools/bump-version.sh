#!/bin/zsh

set -eo pipefail

# ensure we are in the right repo
if ! grep -q  'url = git@github.com:chrocapix/utilz\.git' .git/config; then
	print >&2 "error: not in an utilz repo"
	exit 2
fi

if [[ "$(git describe --all)" != heads/main ]] then
	print >&2 "error: not on main branch"
	exit 2
fi

print "checking origin/main..."
git fetch --dry-run | while read line; do
	print >&2 "error: branch not up to date with origin, pull and try again"
	exit 2
done
print "up to date with origin"

maybe_version="$(grep 'zig fetch' README.md | sed -e 's_.*refs/tags/__' -e 's_\.tar\.gz__')"

git tag | while read line; do
	if [[ $line == $maybe_version ]] then
		current="$maybe_version"
		break
	fi
done
if [[ -z "$current" ]] then
	print >&2 "cannot find current version"
	exit 2
fi

prefix=${current%.*}.
suffix=${current##*.}

if [[ $prefix$suffix != $current ]] then
	print >&2 "error: cannot understand version '$current'"
	exit 2
fi


next=$prefix$((suffix + 1))

if [[ -n "$(git tag -l $next)" ]] then
	print >&2 "error: tag already exists: $next"
	exit 2
fi

print "bumping version: $current -> $next"

sed -i -e "s/${current//./\\.}/$next/" README.md

print "building and testing..."
zig build test

print "committing changes..."
git add README.md
git commit -e -m "Set version to $next"

git tag $next
print "tagged $next"

print "use git push --tags to publish the new version"

