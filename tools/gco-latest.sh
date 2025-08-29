#!/bin/zsh

set -eo pipefail

# ensure we are in the right repo
if ! grep -q  'url = .*github.com[:/]chrocapix/utilz\.git' .git/config; then
	print >&2 "error: not in an utilz repo"
	exit 2
fi

print "fetching tags..."
git fetch --all
git fetch --tags

tag=$(git describe $(git rev-list --tags --max-count=1))
# tag="$(git describe --tags --abbrev=0)"

if [[ -z "$tag" ]] then
	print >&2 "error: no tags"
	exit 2
fi

print "selected tag: $tag"
git checkout $tag
