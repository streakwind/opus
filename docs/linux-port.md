# Linux GTK app

Opus on Linux uses the same `OpusCore` SQLite engine as macOS, with a GTK 4 shell and a testable `OpusGTKSupport` presentation layer. Navigation, lists, tasks, progress, assessments, Calendar, Schedule, Rhythm, settings, export, and Quick Start match macOS functionally with native GTK controls.

## Install (Ubuntu 24.04+)

Download `Opus-linux-x86_64.tar.gz` from [GitHub Releases](https://github.com/streakwind/opus/releases), then:

```sh
mkdir -p ~/.local/opt/opus
tar -xzf Opus-linux-x86_64.tar.gz -C ~/.local/opt/opus
ln -sf ~/.local/opt/opus/bin/opus ~/.local/bin/opus
opus
```

The archive is self-contained: Swift runtime, GTK 4, SQLite, schemas, and loaders ship beside the binary. You do **not** need a system Swift or GTK development install to run it. Only a normal desktop (glibc, display server/drivers) is required. Always launch `bin/opus`, not `libexec/opus`. See `share/doc/opus/INSTALL.md` inside the archive.

## Build from source

Install [Swift 6.1+](https://www.swift.org/install/linux/) and:

```sh
sudo apt-get install libgtk-4-dev libsqlite3-dev pkg-config
swift test
./scripts/build-linux.sh
./dist/linux/bin/opus
```

`build-linux.sh` stages a relocatable tree under `dist/linux` and produces `dist/Opus-linux-x86_64.tar.gz`.

## Features

- Sidebar: Today, Tasks, Inbox, Archive, Calendar, Schedule, Rhythm, and custom lists
- Unified work editor for tasks, page progress, and assessments
- Calendar day/week/month with drag rescheduling
- Schedule day/week hour grid with class blocks and timed events
- Rhythm rules for tasks, progress, assessments, and schedule events
- Settings: System/Light/Dark appearance, JSON export, reveal database folder
- Quick Start help and first-run setup
- Undo, search, archive delete-all confirmation

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Ctrl+N | New work item |
| Ctrl+Enter | Save editor |
| Escape | Cancel editor |
| Ctrl+Shift+Z | Undo |
| F1 | Quick Start |
| Ctrl+Q | Quit |

## Data

Linux stores data at `$XDG_DATA_HOME/opus/Opus.sqlite`, falling back to `~/.local/share/opus/Opus.sqlite`. Set `OPUS_DATA_DIR` to isolate test databases. Quit before copying the database; include `-wal`/`-shm` if present.

## Architecture

- `OpusCore` — SQLite, recurrence, undo, calendar/schedule layout
- `OpusGTKSupport` — navigation, filtering, drafts, session reducer (unit-tested on macOS and Linux)
- `GTKBridge` — C widgets and events
- `OpusGTK` — thin Swift adapter over the session

Interactive controls expose stable accessibility names for automated checks (`scripts/test-linux-ui.py`).

## CI and releases

Linux and macOS workflows run on **manual dispatch** or **version tags** (`v*`), not on ordinary commits. Tagging with `./scripts/release.sh 0.2.0` builds both platforms, verifies the self-contained Linux archive in a clean runtime, and publishes GitHub Release assets.
