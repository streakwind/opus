#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Linux ]]; then
  echo 'Build this target on Linux with Swift 6.1+, GTK 4, and SQLite development packages.' >&2
  exit 1
fi
pkg-config --exists gtk4 sqlite3
swift build -c release --product opus
mkdir -p dist/linux/libexec dist/linux/bin dist/linux/share/applications dist/linux/share/icons/hicolor/256x256/apps
cp .build/release/opus dist/linux/libexec/opus
cp packaging/linux/opus dist/linux/bin/opus
cp packaging/linux/io.github.streakwind.opus.desktop dist/linux/share/applications/
cp Assets/Opus.iconset/icon_256x256.png dist/linux/share/icons/hicolor/256x256/apps/io.github.streakwind.opus.png
tar -czf dist/Opus-linux-preview.tar.gz -C dist/linux .
printf 'Built dist/linux. This build requires the Swift runtime, GTK 4, and SQLite on the target machine.\n'
