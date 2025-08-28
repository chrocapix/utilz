#!/bin/zsh

set -eo pipefail

# ensure we are in the right repo
if ! grep -q  'url = git@github.com:chrocapix/utilz\.git' .git/config; then
	print >&2 "error: not in an utilz repo"
	exit 2
fi

print "fetching tags..."
git fetch --tags

tag="$(git describe --tags --abbrev=0)"

if [[ -z "$tag" ]] then
	print >&2 "error: no tags"
	exit 2
fi

print "selected tag: $tag"
git checkout $tag
