#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --scratch-path /tmp/opus-release
swift scripts/make-icon.swift "$PWD/Assets"
iconutil -c icns Assets/Opus.iconset -o Assets/Opus.icns
mkdir -p dist/Opus.app/Contents/MacOS dist/Opus.app/Contents/Resources
cp Assets/Opus.icns dist/Opus.app/Contents/Resources/OpusStack.icns
cp /tmp/opus-release/release/Opus dist/Opus.app/Contents/MacOS/Opus
cat > dist/Opus.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Opus</string>
<key>CFBundleIdentifier</key><string>com.ruben.opus</string>
<key>CFBundleName</key><string>Opus</string>
<key>CFBundleDisplayName</key><string>Opus</string>
<key>CFBundleIconFile</key><string>OpusStack.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - dist/Opus.app
print "Built: $PWD/dist/Opus.app"
