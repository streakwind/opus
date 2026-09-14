# Fix status — all eight addressed

The findings below are the historical inspection record. All eight are now fixed:

- Rhythm cleanup preserves annotated occurrences and occurrences explicitly referenced by journal entries, journal documents, or list notes. Their IDs and contents remain unchanged, while untouched, unreferenced occurrences continue to follow rhythm edits.
- Cleanup checks the originating item kind, preserving manual task/assessment conversions.
- Linux schedule saves preserve the stored occurrence date when the bridge omits it.
- Today resets both calendar/schedule anchors; calendar selection follows navigation.
- Schedule and rhythm date fields reject impossible dates and invalid repeat boundaries.
- Rhythm payload parsing preserves pipes and multiline notes.
- Both the Swift and GTK calendar display limits are removed. All items render inside the existing scrollable calendar. The original inspection missed an additional GTK four-item cap; it too is removed.

Verification: **126 tests passed with no expected-failure wrappers.** Added coverage for all note-bearing occurrence types, journal/list-note references, conversions, Today, recurrence identity, valid leap days and invalid dates, and pipe-delimited notes. Added a native Linux accessibility regression for eight items on a day; Python syntax verification passed, but native GTK execution is unavailable on this Mac. No production database was used.

---

# Second inspection — September 13, 2026

Reviewed the current working tree, including the five recent fixes. No production source was changed during this pass. The three user-confirmed intended behaviors were excluded from findings: retaining today/history on all-events deletion, Return inserting after journal selections, and excluding planned-only tasks from Calendar.

## Findings

### 1. P1 — Editing a rhythm erases notes on its occurrences

**Location:** `Sources/OpusCore/Store.swift:381–406`.

**Reproduction:** Create a daily task rhythm. On Linux, edit one generated task and add only Notes. Rename the rhythm. The original task is deleted and regenerated without its notes. Pausing the rhythm can likewise remove that annotated occurrence. The same omission exists for assessment topics and schedule notes.

**Cause:** `removeUntouched` does not consider notes/topics when deciding whether an occurrence has been edited. Startup now correctly preserves notes, but rhythm maintenance still deletes them through a separate path.

**Evidence:** `SecondInspectionTests.testRhythmEditPreservesOccurrenceNotes` confirms the annotated task is removed.

**Fix direction:** Treat notes/topics as user modifications when determining replaceable occurrences. Prefer preserving stable occurrence identities and updating only fields inherited from the rule.

### 2. P2 — Editing a rhythm breaks explicit journal embeds

**Location:** `Sources/OpusCore/Store.swift:381–419`.

**Reproduction:** Create a recurring task, insert a link to a specific occurrence in a journal document, then rename the rhythm. The occurrence is removed and regenerated with a new UUID; the journal still refers to its old UUID and opens a missing item.

**Cause:** Regeneration treats an explicitly referenced occurrence as disposable. No ID remapping is applied to journal documents or linked entries. This is not the intended behavior of keeping historical journal text after deliberately deleting a task: the user only edited the rhythm.

**Evidence:** `SecondInspectionTests.testRhythmEditKeepsExplicitJournalLinkResolvable` confirms that the referenced ID no longer resolves after a rhythm title edit. The test seeds a task embed directly; the current general picker normally groups rhythms, while explicit occurrence links remain a supported persisted link type.

**Fix direction:** Preserve IDs for surviving occurrences, or migrate all references atomically when replacing them. Include list-note references as well as journal documents.

### 3. P2 — Rhythm edits undo task-to-assessment conversions

**Location:** `Sources/OpusCore/Store.swift:383–384`.

**Reproduction:** In Calendar, convert a generated task into an assessment without changing its title/date/list. Then edit the original task rhythm's title. The assessment is deleted and replaced by a task.

**Cause:** The recent conversion fix correctly preserves recurrence identity, but assessment cleanup only compares the title, date, and list. It does not check that the originating rule actually generated assessments. Consequently it classifies a manually converted assessment as untouched.

**Evidence:** `SecondInspectionTests.testConvertedOccurrenceSurvivesRhythmEdit` confirms the converted assessment disappears. This is a newly identified edge case in the recent fix, not a repeat of the original failed conversion action.

**Fix direction:** Track explicit overrides or check item kind against the originating rule before treating an occurrence as replaceable.

### 4. P2 — Linux schedule saves lose the original recurrence date

**Locations:** `Sources/OpusGTK/OpusGTK.swift:295–306`; `Sources/OpusGTKSupport/Session.swift:311`.

**Reproduction:** Open a recurring schedule event in the Linux editor and move it to another date. Save, then use This and following on that event. The operation now uses the moved date rather than its original occurrence position, potentially selecting the wrong part of the series.

**Cause:** The GTK save payload does not include `occurrence`. Its reconstructed draft therefore defaults that field to nil. The session loads the existing block but overwrites its stored occurrence with the missing field. Even a title-only save clears the original date; moving it later exposes the scope error.

**Evidence:** `SecondInspectionTests.testLinuxScheduleSavePreservesOriginalOccurrenceWhenBridgeOmitsIt` submits the same draft fields as the bridge and confirms the persisted occurrence becomes nil. Native GTK was not run.

**Fix direction:** Preserve occurrence identity from the stored block; it is not an editable field and should not be reconstructed from widget payloads.

### 5. P2 — Linux Today navigation buttons do nothing

**Locations:** `Sources/GTKBridge/OpusViews.c:403–404`; `Sources/OpusGTKSupport/Session.swift:338–341`, `356–358`.

**Reproduction:** Navigate Calendar or Schedule several weeks forward, then click Today. The view remains on the future date.

**Cause:** GTK sends a navigation delta of zero for Today. Both session handlers interpret that as adding zero days/months to the existing anchor rather than resetting it.

**Evidence:** `SecondInspectionTests.testLinuxTodayButtonsResetAnchor` confirms both anchors remain 90 days in the future.

**Fix direction:** Handle zero as the Today action, resetting the anchor and relevant selection, or use a distinct event for Today.

### 6. P2 — Linux accepts impossible schedule dates and hides the saved event

**Location:** `Sources/OpusGTKSupport/Drafts.swift:288–292`.

**Reproduction:** In the Linux schedule editor's free-form Day field, enter `2026-02-31` and save. Validation succeeds and SQLite stores that exact invalid string. No real displayed calendar day matches it, so the event disappears from the schedule.

**Cause:** Schedule validation checks title, duration, and repeat weekdays but does not validate the date. Work-item validation already contains a date round-trip check, but schedule drafts do not use it.

**Evidence:** `SecondInspectionTests.testLinuxScheduleRejectsImpossibleDate` confirms validation accepts the input and the session saves it.

**Fix direction:** Validate all free-form day/start/end fields consistently before saving, including repeat boundaries.

### 7. P2 — A pipe character truncates Linux rhythm notes

**Locations:** `Sources/GTKBridge/OpusEditors.c:226–229`; `Sources/OpusGTK/OpusGTK.swift:282–291`.

**Reproduction:** Enter `Read A | compare B` in a rhythm's Notes field, save, and reopen. Only `Read A ` is retained. Markdown table rows are affected too.

**Cause:** C serializes `start|end|notes`. Swift permits three splits, then reads only field 2. A pipe within Notes creates field 3, which is discarded. The schedule decoder uses two splits and preserves its final notes field; the rhythm decoder does not.

**Evidence:** Source-traced across the actual serializer and decoder, not executed through native GTK.

**Fix direction:** Limit splitting to the two metadata separators or use a structured payload.

### 8. P2 — Linux Calendar silently hides the sixth and later item on a day

**Location:** `Sources/OpusGTK/OpusGTK.swift:154`.

**Reproduction:** Put six unfinished tasks/assessments on one date. Calendar renders only five. Switching to Day view still renders only five; there is no overflow indicator or action to reveal the rest.

**Cause:** The render loop unconditionally uses `day.items.prefix(5)` for every calendar period and emits no overflow UI. This concerns dated work, not the intended exclusion of planned-only tasks.

**Evidence:** Source-traced through the renderer and GTK day/item widgets. The records remain in storage and may be found outside Calendar.

**Fix direction:** Add a visible overflow count/action, or render a scrollable complete list in Day view.

## Verification and limits

Added six targeted tests in `Tests/OpusGTKSupportTests/SecondInspectionTests.swift`. They use isolated temporary databases and the production store/session code. Assertions for the six reproduced bugs are explicitly wrapped in `XCTExpectFailure`; they are not fixes. The file is macOS-guarded because this expected-failure API is Apple XCTest-specific, though it exercises shared and Linux-support logic.

Full run: **122 tests, zero unexpected failures**, including the six expected bug reproductions. Native pasteboard access was enabled for existing AppKit tests. Native GTK UI, Linux packaging, production databases, and an actual update installation were not exercised.

```sh
CLANG_MODULE_CACHE_PATH=/tmp/opus-clang-cache swift test --disable-sandbox
```

The pass also reviewed journal/list-note autosave, native editor selection/update handling, updater replacement, and date/model validation. No additional issue in those paths is presented here without sufficient evidence. Prioritize occurrence-note preservation and the recurrence identity/reference issues before cosmetic or navigation fixes.
