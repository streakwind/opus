# Opus

A local-first native macOS study planner built with SwiftUI and SQLite. Requires macOS 14 or later and Xcode's Swift 6 toolchain to build. No third-party dependencies, network service, or account.

## Run

```sh
./scripts/build-app.sh
open dist/Opus.app
```

Open `Package.swift` in Xcode to edit and run the executable, or use `swift run`. The app bundle is the preferred way to launch with normal Mac window behavior.

## Use

New installations start empty; users create their own lists and rhythms.
- **⌘N** adds in context: inline task entry in lists, an entry on the selected calendar date, or a timed Schedule block. Type a title and press Return to add it and keep typing. List, task type, and optional deadline appear when the entry field is focused. Select a row for an autosaving details/notes panel.
- **Today** includes work planned or due through tomorrow, plus overdue work. Old recurring tasks do not accumulate unless overdue. **All tasks** also shows unscheduled work. Right-click a task to plan it for today or tomorrow.
- For notes on pages 206–235, use Start 206, Finish 235, Finished through 205. Edit the last-read page directly beside the task title; the standard checkbox marks completion. Lower the stopping point to correct an entry. A simple pace suggestion divides remaining work across calendar days through the deadline.
- Practice and vocabulary tasks use the same checkbox interaction as other tasks. Existing session history remains available in Details. New tasks offer simple tasks or page progress.
- **Calendar** combines planned tasks, deadlines, and assessments in week and month views. Click a date to add there, click an item to edit, and use the checkbox to complete a task directly. The toolbar Add action follows the last selected date. Overflow opens the full day list.
- **Schedule** shows timed classes and study blocks. Enable Class time when editing a list, choose weekdays/time/length, to display its class block. Tasks and assessments stay in Calendar. Class times are configured by the user.
- **Rhythm** repeats tasks, assessments, or scheduled blocks on any combination of weekdays, including every day or Monday–Wednesday. Choose a week interval and optional end date. Generation preserves worked-on, completed, moved, and individually edited occurrences; deleted occurrences remain skipped.
- Edit a list from its sidebar context menu. Removing it moves tasks to Inbox, retains assessments as personal, and removes its recurrence rules.
- **⌥⌘Z** (or the toolbar Undo button) undoes the last saved task/list/calendar change, including deletion, during the current app session. Standard **⌘Z** remains native text undo inside editors. The bottom-left menu exports all records to JSON and reveals the database in Finder.
- Task rows support drag reordering in **My order**, or use the View menu to sort by due date and show completed tasks.
- Inbox holds items without a course/list. Task notes controls are omitted; legacy note data remains in storage and JSON exports.
- The original teal stacked-pages mark is packaged as the Dock/Finder icon by drawing code in `scripts/make-icon.swift`, with an `.icns` containing standard and Retina sizes.

## Storage

The app saves to `~/Library/Application Support/Opus/Opus.sqlite`. For isolated development runs, set `OPUS_DATA_DIR` to another directory. SQLite uses WAL, foreign-key checks, bound parameters, and atomic transactions. Each collection has relational identifiers and typed JSON payloads, with ordering columns and a version-two schema (existing version-one databases migrate automatically). Records are loaded into an observable in-memory store; small local datasets are committed as a transaction per edit. Save failures retain the preceding in-memory and disk state and display an error.

JSON export is a portable snapshot, not a live SQLite file copy. Do not copy only the `.sqlite` file while the app is running because recent writes can be in its WAL file. Future schema changes need explicit numbered migrations before the version is incremented.

## Verification

```sh
swift test --scratch-path /tmp/opus-build
./scripts/build-app.sh
```

Tests cover reopening SQLite with Unicode and multiline content, failed-transaction rollback, page arithmetic, recurrence deduplication/skipping/moving, list deletion and undo, progress correction, calendar date boundaries, month/week grid boundaries, drag rescheduling with a single calendar day per task, archive delete-all, custom list colors, persisted manual task order, legacy database migration, custom recurrence days and intervals, overlapping schedule blocks, and concurrent notes/progress edits.

GitHub Actions runs the same test command on macOS and uploads `dist/Opus.app` as an artifact (see `.github/workflows/macos.yml`). Linux packaging is deferred.

## Current scope

The app includes editable lists/tasks, direct textbook progress, practice history, a unified calendar, a separate timed schedule, flexible repeating rules, undo, JSON export, an Archive with delete-all, and System/Light/Dark appearance. It does not yet include sync, JSON import, automatic backups, reminders, or archived lists. Preparation tasks copy assessment details when created; they are not linked for automatic updates. App signing is local/ad hoc, not notarized distribution.

## Interface references

The interface uses progressive disclosure and low-effort actions from the [GNOME design principles](https://developer.gnome.org/hig/principles.html), compact checklist interaction inspired by [Apple Notes](https://support.apple.com/en-ca/guide/notes/apd93c815aa0/mac), month/week navigation inspired by [Google Calendar](https://support.google.com/calendar/answer/6110849?co=GENIE.Platform%3DDesktop&hl=en-GB), and plain-text Markdown/checklists familiar from [Obsidian](https://help.obsidian.md/syntax). It remains a SwiftUI/AppKit Mac app with system controls.
