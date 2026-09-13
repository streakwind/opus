got tired of using apple notes, google calendar, and obsidian to manage my tasks (there were components of each that I liked). vibecoded an app for this in 3 days with GPT 6 and GPT 5.6. linux and mac only at the moment 

# Opus

A local-first study planner with a native macOS SwiftUI app and a self-contained Linux GTK app. Both share one Swift/SQLite core. Requires macOS 14+ (Xcode Swift 6) to build the Mac app. No third-party dependencies, network service, or account.

Linux packaging and parity details: [docs/linux-port.md](docs/linux-port.md).

## Run (macOS)

```sh
./scripts/build-app.sh
open dist/Opus.app
```

Open `Package.swift` in Xcode to edit and run the executable, or use `swift run`. The app bundle is the preferred way to launch with normal Mac window behavior.

## Run (Linux)

Download `Opus-linux-x86_64.tar.gz` from Releases, extract it, and run `bin/opus`. No separate Swift or GTK install is required. To build from source on Ubuntu 24.04:

```sh
sudo apt-get install libgtk-4-dev libsqlite3-dev pkg-config
./scripts/build-linux.sh
./dist/linux/bin/opus
```

## Use

- New installations start empty. Add your own lists and rhythms; no personal course or timetable defaults are shipped.
- **⌘N** / **Ctrl+N** adds in context. Type a title and press Return to add it and keep typing. List, task type, and optional deadline appear when editing.
- **Today** includes work planned or due through tomorrow, plus overdue work. Old recurring tasks do not accumulate unless overdue. **Tasks** also shows unscheduled work.
- For notes on pages 206–235, use Start 206, Finish 235, Finished through 205. Edit the last-read page beside the task title.
- **Calendar** combines planned tasks, deadlines, and assessments in day, week, and month views. Drag items to reschedule.
- **Schedule** shows timed classes and study blocks. Enable class times when editing a list.
- **Rhythm** repeats tasks, assessments, progress, or scheduled blocks on weekdays with optional week intervals and end dates.
- **⌥⌘Z** / **Ctrl+Shift+Z** (or Undo) undoes the last saved change during the current session. Settings exports JSON and reveals the database folder.
- Inbox holds items without a course/list.

## Journal

Journal and list notes share an **Edit / Preview** control. Edit keeps Markdown and LaTeX source stable under the caret; Preview renders prose and equations without duplicating the source. Use `$…$` for inline math and `$$…$$` for display math. Fenced code supports language names such as `swift`, `python`, `cpp`, and `js`, with highlighting even before the closing fence is typed. Return continues lists, checkboxes, and code indentation; an empty list item ends the list. ⌘B and ⌘I insert Markdown formatting. Switching to Preview preserves the editing caret and undo history.

Each day is one continuous Markdown document. Type `/task` at the caret to embed work, then keep writing. Arrow keys and Shift-selection move through text and embeds; standard copy, paste, delete, and ⌘Z work across both. Double-click an embed, or select it and press ⌘Return, to open its linked item. Removing an embed affects that day only, leaving the task and older entries intact. Existing embed comments remain available in the linked item's editor.

## Storage

- macOS: `~/Library/Application Support/Opus/Opus.sqlite`
- Linux: `~/.local/share/opus/Opus.sqlite` (or `$XDG_DATA_HOME/opus`)
- Override with `OPUS_DATA_DIR` for isolated runs

SQLite uses WAL, foreign-key checks, bound parameters, and atomic transactions. JSON export is a portable snapshot, not a live file copy. Quit before copying the database; include `-wal`/`-shm` if present.

## Verification

```sh
swift test --scratch-path /tmp/opus-build
./scripts/build-app.sh          # macOS
./scripts/build-linux.sh        # Linux
```

Shared and presentation tests run on both platforms. Linux CI also builds the self-contained archive, smoke-tests under Xvfb, runs accessibility UI checks, and verifies the archive in a clean Ubuntu runtime without Swift/GTK packages.

## Releases

Workflows run only on **manual dispatch** or **version tags**, never on ordinary commits:

```sh
./scripts/release.sh 0.2.0
```

That tags `v0.2.0`, builds macOS ZIP + Linux archive, and publishes a GitHub Release.

## Current scope

Editable lists/tasks, textbook progress, unified calendar, timed schedule, flexible rhythms, undo, JSON export, Archive with delete-all, and System/Light/Dark appearance on both platforms. Not yet included: sync, JSON import, automatic backups, reminders, or archived lists. App signing is local/ad hoc; releases are not notarized.

Settings includes Quick Start. It never inserts sample tasks or changes your data.

Interface inspiration: [GNOME HIG](https://developer.gnome.org/hig/principles.html), [Apple Notes](https://support.apple.com/en-ca/guide/notes/apd93c815aa0/mac), [Google Calendar](https://support.google.com/calendar/answer/6110849?co=GENIE.Platform%3DDesktop&hl=en-GB), and plain Markdown checklists.
