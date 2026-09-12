#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if (( $# == 1 )); then
  version="$1"
elif (( $# == 3 )); then
  version="$1.$2.$3"
else
  print -u2 "Usage: $0 0.2.0"
  print -u2 "   or: $0 0 2 0"
  exit 64
fi
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$' ]]; then
  print -u2 "Invalid version: $version"
  exit 64
fi

for command in git gh; do
  if ! command -v "$command" >/dev/null 2>&1; then
    print -u2 "Required command not found: $command"
    exit 1
  fi
done
if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "The working tree must be clean before releasing."
  exit 1
fi
gh auth status >/dev/null

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  print -u2 "Release from a branch, not a detached HEAD."
  exit 1
fi
git fetch origin "$branch"
sha="$(git rev-parse HEAD)"
remote_sha="$(git rev-parse "origin/$branch")"
if [[ "$sha" != "$remote_sha" ]]; then
  print -u2 "Push $branch before releasing."
  exit 1
fi

tag="v$version"
if git rev-parse "$tag" >/dev/null 2>&1 || gh release view "$tag" >/dev/null 2>&1; then
  print -u2 "$tag already exists."
  exit 1
fi

git tag "$tag"
git push origin "$tag"
print "Tagged $tag. GitHub Actions will build macOS/Linux artifacts and publish the release."
print "Watch progress with: gh run watch"
