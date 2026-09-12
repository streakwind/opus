# Native Mac and Linux

## Decision

Keep the existing SwiftUI/AppKit Mac interface. Build a separate GTK 4 Linux interface around shared Swift models, persistence, and scheduling logic. This is a port plan, not a claim that the current application builds on Linux.

Swift supports Linux development and deployment: https://www.swift.org/platform-support/
GTK supplies native Linux desktop controls: https://www.gtk.org/

## Reusable code

`Models.swift`, `Database.swift`, and `CalendarLayout.swift` primarily use Foundation and SQLite. Move these into an `OpusCore` library, together with recurrence, page progress, and task mutation logic from `Store.swift`. Preserve record IDs and schema compatibility. Move the Color/AppKit extensions out of Store into the Mac target. Keep file dialogs, window behavior, and appearance in each platform's UI.

The Linux shell should use GTK 4 via a small C interoperability boundary or a maintained Swift binding after a focused compatibility spike. Do not duplicate recurrence or SQLite write logic in a second language. SwiftUI lookalike frameworks can be evaluated, but replacing the working Mac UI is not required.

## Delivery sequence

1. Extract OpusCore with the existing behavioral tests and run it on macOS and Linux CI.
2. Prove GTK integration with one window, task entry, completion, lists, and database reopening.
3. Add textbook page entry, Calendar, Schedule, and Rhythm using the same core commands.
4. Implement Linux file dialogs, keyboard shortcuts, Settings/tutorial, and accessible focus behavior.
5. Package and test on a named Linux distribution; choose Flatpak or distribution packages after verifying runtime dependencies.

Linux storage should use `$XDG_DATA_HOME/opus` (fallback `~/.local/share/opus`). Retain `OPUS_DATA_DIR` for isolated testing. Never ship example personal records. Both apps start empty.

## Limits

Shared storage format does not imply sync. Do not point two running apps at the same SQLite file through a cloud-synced folder. Add a validated import/export or explicit sync design separately. Linux compilation, desktop integration, and packaging require a Linux runner before claiming support.
