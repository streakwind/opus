#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if (( $# == 1 )); then
  version="$1"
elif (( $# == 3 )); then
  version="$1.$2.$3"
else
  print -u2 "Usage: $0 0.3.0"
  print -u2 "   or: $0 0 3 0"
  exit 64
fi
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$' ]]; then
  print -u2 "Invalid version: $version"
  exit 64
fi

for command in git gh ditto plutil; do
  if ! command -v "$command" >/dev/null 2>&1; then
    print -u2 "Required command not found: $command"
    exit 1
  fi
done
if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "Run this release script on macOS."
  exit 1
fi
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
  print -u2 "Push $branch before releasing, then wait for Linux CI to pass."
  exit 1
fi

tag="v$version"
if git rev-parse "$tag" >/dev/null 2>&1 || gh release view "$tag" >/dev/null 2>&1; then
  print -u2 "$tag already exists."
  exit 1
fi

run_id="$(gh run list \
  --workflow Linux \
  --commit "$sha" \
  --status success \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"
if [[ -z "$run_id" ]]; then
  print -u2 "No successful Linux workflow found for $sha."
  print -u2 "Wait for Linux CI to finish, then run this script again."
  exit 1
fi

build_number="${OPUS_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
OPUS_VERSION="$version" OPUS_BUILD_NUMBER="$build_number" ./scripts/build-app.sh

mkdir -p dist
rm -f dist/Opus-macOS.zip dist/Opus-linux-preview.tar.gz
ditto -c -k --keepParent dist/Opus.app dist/Opus-macOS.zip

download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT
gh run download "$run_id" \
  --name Opus-linux-preview \
  --dir "$download_dir"
cp "$download_dir/Opus-linux-preview.tar.gz" dist/

plutil -extract CFBundleShortVersionString raw \
  dist/Opus.app/Contents/Info.plist | grep -qx "$version"

gh release create "$tag" \
  dist/Opus-macOS.zip \
  dist/Opus-linux-preview.tar.gz \
  --target "$sha" \
  --title "Opus $version" \
  --generate-notes \
  --prerelease

git fetch origin tag "$tag"
print "Created GitHub prerelease $tag"
