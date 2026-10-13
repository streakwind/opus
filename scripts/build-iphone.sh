#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:-simulator}"
common=(-project Apple/Opus.xcodeproj -scheme "Opus iPhone" -configuration Release -derivedDataPath /tmp/opus-iphone)
case "$mode" in
  simulator)
    xcodebuild "${common[@]}" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
    print "Simulator app: /tmp/opus-iphone/Build/Products/Release-iphonesimulator/Opus iPhone.app"
    ;;
  archive)
    if [[ -z "${OPUS_DEVELOPMENT_TEAM:-}" ]]; then
      print -u2 'Set OPUS_DEVELOPMENT_TEAM to your Apple Developer team ID (or archive in Xcode).'
      exit 1
    fi
    xcodebuild "${common[@]}" -destination 'generic/platform=iOS' -archivePath "$PWD/dist/Opus-iPhone.xcarchive" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM="$OPUS_DEVELOPMENT_TEAM" \
      OPUS_ICLOUD_CONTAINER="${OPUS_ICLOUD_CONTAINER:-iCloud.com.ruben.opus}" archive
    if [[ -n "${OPUS_EXPORT_OPTIONS:-}" ]]; then
      xcodebuild -exportArchive -archivePath "$PWD/dist/Opus-iPhone.xcarchive" \
        -exportPath "$PWD/dist/iPhone" -exportOptionsPlist "$OPUS_EXPORT_OPTIONS" -allowProvisioningUpdates
    fi
    print 'Archive ready. Export for registered devices in Xcode Organizer, or provide OPUS_EXPORT_OPTIONS.'
    ;;
  *) print -u2 'Usage: scripts/build-iphone.sh [simulator|archive]'; exit 1 ;;
esac
