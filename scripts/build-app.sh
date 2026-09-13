#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

latest_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
version="${OPUS_VERSION:-${latest_tag#v}}"
version="${version:-0.0.0}"
build_number="${OPUS_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$' ]]; then
  print -u2 "Invalid OPUS_VERSION: $version"
  exit 1
fi
if [[ ! "$build_number" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "Invalid OPUS_BUILD_NUMBER: $build_number"
  exit 1
fi

sdk="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${sdk%%.*} < 26 )); then
  print -u2 "Need the macOS 26 SDK for the current sidebar. This build is using $sdk."
  exit 1
fi

swift build -c release --scratch-path /tmp/opus-release
if [[ "${OPUS_REGENERATE_ICON:-0}" == "1" ]]; then
  swift scripts/make-icon.swift "$PWD/Assets"
  iconutil -c icns Assets/Opus.iconset -o Assets/Opus.icns
fi
if [[ ! -f Assets/Opus.icns ]]; then
  print -u2 "Assets/Opus.icns is missing. Run with OPUS_REGENERATE_ICON=1."
  exit 1
fi

rm -rf dist/Opus.app
mkdir -p dist/Opus.app/Contents/MacOS dist/Opus.app/Contents/Resources
cp Assets/Opus.icns dist/Opus.app/Contents/Resources/OpusStack.icns
cp /tmp/opus-release/release/Opus dist/Opus.app/Contents/MacOS/Opus
math_bundle=""
if [[ -d /tmp/opus-release/release/SwiftMath_SwiftMath.bundle ]]; then
  math_bundle=/tmp/opus-release/release/SwiftMath_SwiftMath.bundle
elif [[ -d /tmp/opus-release/arm64-apple-macosx/release/SwiftMath_SwiftMath.bundle ]]; then
  math_bundle=/tmp/opus-release/arm64-apple-macosx/release/SwiftMath_SwiftMath.bundle
fi
if [[ -n "$math_bundle" ]]; then
  cp -R "$math_bundle" dist/Opus.app/Contents/Resources/SwiftMath_SwiftMath.bundle
fi
cat > dist/Opus.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Opus</string>
<key>CFBundleIdentifier</key><string>com.ruben.opus</string>
<key>CFBundleName</key><string>Opus</string>
<key>CFBundleDisplayName</key><string>Opus</string>
<key>CFBundleIconFile</key><string>OpusStack.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - dist/Opus.app
print "Built Opus $version ($build_number): $PWD/dist/Opus.app"
