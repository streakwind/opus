#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Linux ]]; then
  echo 'Build this target on Linux with Swift 6.1+, GTK 4, and SQLite development packages.' >&2
  exit 1
fi
pkg-config --exists gtk4 sqlite3
swift build -c release --product opus \
  -Xlinker -rpath -Xlinker '$ORIGIN/../lib' \
  -Xlinker -rpath -Xlinker '$ORIGIN/../lib/swift/linux'

rm -rf dist/linux
mkdir -p \
  dist/linux/libexec \
  dist/linux/bin \
  dist/linux/lib/swift/linux \
  dist/linux/share/applications \
  dist/linux/share/icons/hicolor/256x256/apps \
  dist/linux/share/glib-2.0/schemas \
  dist/linux/share/doc/opus

cp .build/release/opus dist/linux/libexec/opus
cp packaging/linux/opus dist/linux/bin/opus
chmod +x dist/linux/bin/opus dist/linux/libexec/opus
cp packaging/linux/io.github.streakwind.opus.desktop dist/linux/share/applications/
cp Assets/Opus.iconset/icon_256x256.png dist/linux/share/icons/hicolor/256x256/apps/io.github.streakwind.opus.png
cp packaging/linux/INSTALL.md dist/linux/share/doc/opus/
cp packaging/linux/THIRD_PARTY_NOTICES.txt dist/linux/share/doc/opus/ 2>/dev/null || true

./scripts/bundle-linux-runtime.sh
./scripts/verify-linux-bundle.sh

tar -czf dist/Opus-linux-x86_64.tar.gz -C dist/linux .
# Keep the preview name as an alias for existing release tooling.
cp dist/Opus-linux-x86_64.tar.gz dist/Opus-linux-preview.tar.gz
printf 'Built self-contained dist/Opus-linux-x86_64.tar.gz\n'
