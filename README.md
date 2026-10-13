# Opus

A study planner for Mac and iPhone, sharing one Swift/SQLite core. Mac requires macOS 14 or later; iPhone requires iOS 26. Build with Xcode 26 or later.

## Run (macOS)

```sh
./scripts/build-app.sh
open dist/Opus.app
```

Open `Package.swift` in Xcode to edit and run the executable, or use `swift run`. The app bundle is the preferred way to launch with normal Mac window behavior.

## Run (iPhone)

Open `Apple/Opus.xcodeproj`, select **Opus iPhone**, configure your signing team, and Run on your connected phone. No App Store installation is required.

Follow the [iPhone installation and iCloud setup guide](docs/iphone-installation.md) for Developer Mode, free local-only installation, registered-device distribution, and signed Mac/iPhone builds. Both apps must be provisioned for the same iCloud container to sync; the ad-hoc Mac release remains local-only.

For an unsigned simulator build:

```sh
./scripts/build-iphone.sh simulator
```

## Use

- New installations start empty. Add your own lists and rhythms; no personal course or timetable defaults are shipped.
- **⌘N** adds in context. Type a title and press Return to add it and keep typing. List, task type, and optional deadline appear when editing.
- **⌘K** (macOS) opens global search for lists, tasks, progress, assessments, note names, rhythms, schedule blocks, and app pages. Use ↑/↓ and Return to open a result, ⌘1–9 to switch categories, and Escape to close. Completed and past work remains searchable; journal entries and note bodies are excluded.
- **Today** includes work planned or due through tomorrow, plus overdue work. Old recurring tasks do not accumulate unless overdue. **Tasks** also shows unscheduled work.
- For notes on pages 206–235, use Start 206, Finish 235, Finished through 205. Edit the last-read page beside the task title.
- **Calendar** combines planned tasks, deadlines, and assessments in day, week, and month views. Drag items to reschedule.
- **Schedule** shows timed classes and study blocks. Enable class times when editing a list.
- **Rhythm** repeats tasks, assessments, progress, or scheduled blocks on weekdays with optional week intervals and end dates.
- **⌥⌘Z** (or Undo) undoes the last saved change during the current session. Settings exports JSON and reveals the database folder.
- Inbox holds items without a course/list.

## Journal

Journal and list notes use live Markdown preview: the paragraph under the caret exposes its source, while surrounding prose, equations, and code render in place. There is no Edit/Preview switch. Use `$…$` for inline math and `$$…$$` for display math. Fenced code supports language names such as `swift`, `python`, `cpp`, and `js`, with highlighting even before the closing fence is typed. Return continues lists, checkboxes, and code indentation; an empty list item ends the list. ⌘B and ⌘I insert Markdown formatting. Native selection, copy/paste, and undo work across rendered content.

Each journal day starts empty and is independent. Embeds appear only when explicitly inserted; task due dates never carry them into another day. Existing saved daily content is preserved.

Each day is one continuous Markdown document. Type `/task` at the caret to embed work, then keep writing. Arrow keys and Shift-selection move through text and embeds; standard copy, paste, delete, and ⌘Z work across both. Double-click an embed, or select it and press ⌘Return, to open its linked item. Removing an embed affects that day only, leaving the task and older entries intact. Existing embed comments remain available in the linked item's editor.

## Storage

- macOS: `~/Library/Application Support/Opus/Opus.sqlite`
- iPhone: the app container’s `Library/Application Support/Opus/Opus.sqlite`
- Override Mac storage with `OPUS_DATA_DIR` for isolated runs

Optional iCloud Drive sync exchanges item revisions and deletion records while keeping SQLite local. Enable it in Settings on both provisioned apps. See the installation guide for merge behavior and signing requirements.

SQLite uses WAL, foreign-key checks, bound parameters, and atomic transactions. JSON export is a portable snapshot, not a live file copy. Quit before copying the database; include `-wal`/`-shm` if present.

## Verification

```sh
swift test --scratch-path /tmp/opus-build
./scripts/build-app.sh          # macOS
./scripts/build-iphone.sh simulator
# Xcode: select Opus iPhone, then Product > Test
```

Core and Mac presentation tests run on macOS.

## Releases

Workflows run only on **manual dispatch** or **version tags**, never on ordinary commits:

```sh
./scripts/release.sh 0.2.0
```

That tags `v0.2.0`, builds the macOS ZIP, checks simulator/device iPhone builds and UI tests, and publishes the Mac GitHub Release. Installable iPhone IPAs need your team’s signing and registered-device profiles; CI does not publish an unsigned IPA.

## Current scope

Editable lists/tasks, textbook progress, unified calendar, timed schedule, flexible rhythms, undo, JSON export, Archive with delete-all, and System/Light/Dark appearance on Mac. iPhone provides native forms, a day calendar, and Markdown source editing/preview with shared storage and optional iCloud sync. The Mac live math/code editor remains Mac-specific. Not yet included: JSON import, automatic backups, reminders, or archived lists. Public Mac releases use ad-hoc signing and are not notarized; iCloud requires the provisioned Xcode build.

Settings includes Quick Start. It never inserts sample tasks or changes your data.

Interface inspiration: [Apple Notes](https://support.apple.com/en-ca/guide/notes/apd93c815aa0/mac), [Google Calendar](https://support.google.com/calendar/answer/6110849?co=GENIE.Platform%3DDesktop&hl=en-GB), and plain Markdown checklists.
