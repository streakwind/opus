# Linux GTK preview

Opus now has a shared `OpusCore` target and separate SwiftUI (Mac) and GTK 4 (Linux) interfaces. Both use the same SQLite schema, models, task mutations, recurrence engine, and progress calculations. Mac-specific colors and window code remain in the Mac target.

The Linux preview supports Today (including tomorrow), Inbox, All Tasks, Completed, custom lists, task creation/editing/deletion, completion, undo, textbook page tracking, due dates, and Quick Start help. It starts empty. Calendar, Schedule, and Rhythm interfaces are not yet available on Linux; their records remain intact in the shared database.

## Build on Ubuntu 24.04

Install [Swift 6.1 or newer](https://www.swift.org/install/linux/), then:

```sh
sudo apt-get install libgtk-4-dev libsqlite3-dev pkg-config
swift test
./scripts/build-linux.sh
./dist/linux/bin/opus
```

GTK uses the desktop theme and native widgets. The C bridge owns the widgets and forwards user actions to Swift; it contains no database or recurrence logic. The bridge targets GTK 4.8 or newer. [GTK documentation](https://docs.gtk.org/gtk4/).

`dist/linux` contains the executable, desktop entry, and the existing Opus icon. Install under a prefix such as `~/.local` with its `bin` on PATH. The binary currently requires the Swift runtime, GTK, and SQLite to be installed; this is not a self-contained Flatpak. GitHub Actions builds and smoke-tests the preview on Ubuntu using an isolated database.

## Data

Linux stores data at `$XDG_DATA_HOME/opus/Opus.sqlite`, falling back to `~/.local/share/opus/Opus.sqlite`. `OPUS_DATA_DIR` overrides the directory for testing. No personal presets or sample records are included.

To transfer a database, quit Opus on both computers and back up the database before copying it. Copy any accompanying `-wal` and `-shm` files with it if present. Shared storage format does not imply synchronization; do not use a live cloud-synced SQLite file.

## Next

Port Calendar week/month views, Schedule, Rhythm, and list settings. Then validate keyboard navigation, accessibility, Wayland, and packaging on a real Linux desktop before a full Linux release.
