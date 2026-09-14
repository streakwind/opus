# App inspection and fixes — September 13, 2026

## Scope confirmed by the user

Five findings were approved for correction. Three behaviors are intended and remain unchanged: deleting a rhythm's events retains today/history, Return inserts after selected journal text, and Calendar excludes planned tasks without deadlines. The inspection tests now assert those intended behaviors instead of marking them as failures.

## Changes

- **Notes:** Startup preserves task notes, assessment topics, rhythm notes, and schedule notes. The Linux editor's saved notes survive reopening. Previously erased notes cannot be recovered without an earlier export/database copy.
- **Updater:** Copy and validate a staged application on the destination volume before moving the installed bundle. Keep the previous bundle during the swap and restore it if the swap fails. Failed staging leaves the installed app intact. Write the completion marker only after replacement succeeds. Preserve helper output in a temporary log beside its script. Correct the completion-marker command to the macOS `/usr/bin/printf` path.
- **Type conversion:** Mac task-to-assessment saves now take the assessment path. Shared saves remove the source item and create the replacement in one transaction. Recurrence identity is preserved, journal and list-note links are rewritten, and task activities are removed when converting to an assessment because they require a task foreign key. Session Undo restores the entire original item, activity history, and links. Linux conversion works in both directions without duplicate records.
- **Optional deadlines:** New task/progress saves preserve nil deadlines. Saving or editing undated progress no longer adds today's deadline. Assessments retain a required date.
- **Completion:** Save completion immediately; view disappearance can no longer cancel a deferred write. Normal store Undo remains available.

## Verification

Final result: **116 tests passed, zero failures and no expected-failure wrappers.**

The regression suite covers note reopening, both conversion directions, recurrence identity, journal links, atomic undo, persisted undated progress, immediate completion, and updater success/copy failure/invalid bundle/swap failure. Updater tests execute the production replacement script against isolated fake bundles; copy and swap failures are injected and actual application launching is suppressed.

The original Mac and shared test suites are also run. Native GTK UI and production update installation are not exercised. All test databases and fake application bundles are isolated temporary files.

```sh
CLANG_MODULE_CACHE_PATH=/tmp/opus-clang-cache swift test --disable-sandbox
```

Native pasteboard access is required by existing AppKit copy/paste tests; those assertions fail under the restricted sandbox and pass with native-service access.
