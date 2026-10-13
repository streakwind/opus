# Install Opus on iPhone without the App Store

Opus supports iPhone on **iOS 26 or later**. Build on a Mac with **Xcode 26 or later**, including the iOS platform support. The project is `Apple/Opus.xcodeproj`; its shared schemes are **Opus iPhone** and **Opus Mac**. Opening only `Package.swift` does not create an installable iPhone app.

## Install directly with Xcode

1. Open `Apple/Opus.xcodeproj`. In Xcode Settings → Apple Accounts, add your Apple Account.
2. Connect your iPhone, unlock it, and trust the Mac when asked. Select the **Opus iPhone** scheme and your physical iPhone as the run destination.
3. Select the **Opus iPhone** target → Signing & Capabilities. Enable automatic signing and choose your team. Use a unique bundle identifier, such as `com.yourname.opus.iphone`, if the default identifier belongs to another developer.
4. Configure iCloud as described below if your team has an Apple Developer Program membership. For a free Personal Team, follow the local-only instructions instead.
5. Enable **Settings → Privacy & Security → Developer Mode** on iPhone when prompted, restart, and confirm. If iOS asks you to trust your development certificate, do so in **Settings → General → VPN & Device Management**.
6. Press Run (⌘R). Xcode builds, signs, installs, and opens Opus. After installation, launch it from the Home Screen. The app works without keeping the phone connected to the Mac.

See Apple's [device installation instructions](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Enable iCloud on both devices

iCloud needs a developer team with the iCloud capability, correctly provisioned apps, and the same iCloud container on both targets. A free Personal Team cannot provision this capability. Apple's [capability overview](https://developer.apple.com/help/account/capabilities/capabilities-overview) explains membership restrictions.

1. In your developer account's Certificates, Identifiers & Profiles, register an iCloud container owned by your team, for example `iCloud.com.yourname.opus`. Enable iCloud Documents on the App IDs used for both Mac and iPhone. You can also register/select containers through Xcode's Signing & Capabilities → iCloud panel.
2. Set `OPUS_ICLOUD_CONTAINER` in `Apple/Shared.xcconfig` to that identifier. Both targets use `Apple/Opus.entitlements`. In both targets' Signing & Capabilities, select **iCloud Documents** and the same container. If Xcode rewrites the entitlements with literal identifiers, verify they still match on both targets.
3. Choose the same development team on both targets. Let automatic signing regenerate provisioning profiles. A Mac app signed ad hoc with `codesign --sign -` cannot access the container.
4. Build/run **Opus Mac** through Xcode. It opens the existing Mac database at `~/Library/Application Support/Opus/Opus.sqlite`. Quit any older copy of Opus before launching this build.
5. Sign in to the **same Apple Account** on Mac and iPhone and turn on iCloud Drive in system settings. The developer signing account and the user's iCloud account serve different purposes; device sync follows the user's iCloud account.
6. Export the existing Mac data in Settings before enabling sync for the first time. Then turn on **Settings → Sync with iCloud** in Opus on both devices. Initial synchronization merges existing data; neither device is designated as the replacement source.
7. Keep both apps open and use **Sync now**. Apple controls upload/download timing, so delivery may take longer than one polling interval. Create a uniquely named task on Mac, confirm it on iPhone, edit it there, and confirm the edit on Mac.

Read Apple's [iCloud configuration guide](https://developer.apple.com/documentation/xcode/configuring-icloud-services). For troubleshooting, check both profiles, both entitlements, the shared container, iCloud Drive, account identity, and the sync status shown in Opus Settings.

### Command-line builds

After configuring signing in Xcode:

```sh
OPUS_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
OPUS_ICLOUD_CONTAINER=iCloud.com.yourname.opus \
./scripts/build-app.sh

OPUS_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
OPUS_ICLOUD_CONTAINER=iCloud.com.yourname.opus \
./scripts/build-iphone.sh archive
```

The Mac result is `dist/Opus.app`; the phone archive is `dist/Opus-iPhone.xcarchive`. A matching unique bundle identifier must already be set in the relevant Xcode target. Xcode must be signed into your developer account. If the command-line tools are selected instead of Xcode, set `DEVELOPER_DIR` to your installed Xcode's `Contents/Developer` directory or select Xcode in its settings.

## Free Personal Team: local use

You can install a local-only build using a free Apple Account:

1. In the iPhone target's Signing & Capabilities, remove the iCloud capability.
2. Clear **Code Signing Entitlements** in the iPhone target's Build Settings for Debug and Release. Do not delete the shared entitlements file used by a configured Mac target.
3. Select your Personal Team and a unique iPhone bundle identifier, then Run on the phone.
4. Leave Opus's iCloud toggle off. Tasks, notes, and journal remain local; JSON export is available in Settings.

Personal Team provisioning expires **seven days after issuance**, so rebuild/install with Xcode when the app stops opening. Keep the same bundle identifier to update the installed app. Export data before deleting or reinstalling an app; deleting it removes its local storage. See Apple's [developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Install on another registered iPhone

With a paid team, register each recipient's device in your developer account, archive **Opus iPhone** for a physical iOS device, and export from Xcode Organizer for registered devices using the appropriate development or Ad Hoc profile. Install the exported, signed IPA using Xcode's device tools or Apple Configurator. Developer Mode may be required.

For command-line export, supply `OPUS_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist` to `scripts/build-iphone.sh archive`. Use an export-options plist generated for your team and the chosen distribution method. An archive or unsigned simulator app is not a sideloadable IPA, and an IPA provisioned for another device will not install. Profiles/certificates expire; renew and reinstall before expiry to keep using the app. See Apple's [registered-device distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

## Phone interface

The phone uses native Liquid Glass tabs, toolbars, and editor actions, with the Mac list colors and rounded system controls. Today, Tasks, Calendar, Journal, and Rhythm are available through tabs. Editors use scrolling native forms and respect the keyboard, safe areas, and Dynamic Type. Calendar uses a day agenda instead of the Mac's wide week/month grids. Change dates in the editors to reschedule items.

Journal saves as you type; list notes save with Save. iPhone uses native Markdown text editing with a collapsible preview; the Mac's AppKit live math/code editor is not ported to UIKit. Markdown source, including equations and embeds, syncs without conversion. The iPhone preview currently renders standard Markdown; equations remain source text. Use Embed work to add links to a journal day. JSON export uses the iPhone Files picker.

## Sync behavior and storage

SQLite stays local to each app. iCloud Drive receives versioned JSON ledgers, one per installation, in the app's `Documents/OpusSync` container directory. All work, lists, list notes, journal content, rhythms, schedule blocks, and activity records participate. Appearance and undo history are device-local.

Different items edited offline merge. Concurrent changes to the same item use the latest revision's whole item, with a deterministic device tie-break; this is not collaborative character-by-character editing. List notes are part of their parent list record, so concurrent changes to different notes within one list can conflict. Keep device clocks correct. Deletions sync through persistent tombstones. Do not remove ledger files to reset sync; doing so can lose deletion history. Undo history clears when incoming data changes the database, preventing undo from reverting remote work.

Checks occur on activation, on Sync now, and every 20 seconds while the app runs. iOS suspends work in the background. “iCloud checked” confirms a local merge and write, not delivery to every other device. Network loss leaves local editing available; changes upload when iCloud becomes available. Signing out or switching iCloud accounts suspends synchronization to protect the original account's data. Return to the original account before re-enabling sync.

Disabling sync stops cloud reads/writes and preserves local data and existing cloud files. Uninstalling can erase unsynced changes. Export before uninstalling, changing signing identities, or resetting storage.

## Verification before daily use

Run `swift test`, build both Xcode schemes, then run the phone UI tests with Product → Test under **Opus iPhone**. The tests use a temporary database and keep screenshots in the test results.

On the smallest supported iPhone simulator and a large iPhone, check portrait/landscape, light/dark appearance, large accessibility text, keyboard entry, and VoiceOver. Exercise creation/editing/deletion for tasks, progress, assessments, lists/class times, notes, schedule blocks, and rhythms; journal day switching/embeds; export; and navigation while the keyboard is visible.

For sync, use provisioned physical devices: test Mac→phone and phone→Mac, independent offline edits, deletion while the other device is offline, same-item conflict behavior, reconnect/relaunch, and iCloud unavailable/account-change status. Simulator builds and the UI tests do not validate authenticated iCloud delivery.
