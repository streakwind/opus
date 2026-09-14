import Foundation
import XCTest
import OpusCore
@testable import OpusGTKSupport

final class SecondInspectionTests: XCTestCase {
    @MainActor private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(database: Database(url: root.appendingPathComponent("test.sqlite"))))
    }

    @MainActor func testRhythmEditPreservesOccurrenceNotes() async throws {
        try withStore { store in
            var rule = QuizRule(title: "Read", weekdays: Array(1...7), itemKind: .task, startDate: Day.today)
            store.saveRule(rule)
            var task = try XCTUnwrap(store.state.tasks.first)
            task.notes = "My outline"
            store.save(task)
            rule.title = "Read chapter"
            store.saveRule(rule)
            XCTAssertEqual(store.state.tasks.first { $0.id == task.id }?.notes, "My outline")
        }
    }

    @MainActor func testRhythmEditKeepsExplicitJournalLinkResolvable() async throws {
        try withStore { store in
            var rule = QuizRule(title: "Read", weekdays: Array(1...7), itemKind: .task, startDate: Day.today)
            store.saveRule(rule)
            let task = try XCTUnwrap(store.state.tasks.first)
            store.save(JournalEntry(day: Day.today, title: "Journal", markdown: JournalLink.task(task.id).embedToken))
            rule.title = "Read chapter"
            store.saveRule(rule)
            XCTAssertTrue(store.state.tasks.contains { $0.id == task.id })
        }
    }

    @MainActor func testConvertedOccurrenceSurvivesRhythmEdit() async throws {
        try withStore { store in
            var rule = QuizRule(title: "Read", weekdays: Array(1...7), itemKind: .task, startDate: Day.today)
            store.saveRule(rule)
            let task = try XCTUnwrap(store.state.tasks.first)
            store.save(Assessment(id: task.id, title: task.title, day: try XCTUnwrap(task.due)))
            rule.title = "Updated rhythm"
            store.saveRule(rule)
            XCTAssertTrue(store.state.assessments.contains { $0.id == task.id })
        }
    }

    @MainActor func testLinuxTodayButtonsResetAnchor() async throws {
        try withStore { store in
            let session = LinuxSession(store: store)
            session.calendarAnchor = Day.adding(90)
            session.scheduleAnchor = Day.adding(90)
            _ = session.handle(.calendarNavigate(0))
            _ = session.handle(.scheduleNavigate(0))
            XCTAssertEqual(session.calendarAnchor, Day.today)
            XCTAssertEqual(session.scheduleAnchor, Day.today)
        }
    }

    @MainActor func testLinuxScheduleSavePreservesOriginalOccurrenceWhenBridgeOmitsIt() async throws {
        try withStore { store in
            let rule = QuizRule(title: "Class", weekdays: Array(1...7), itemKind: .schedule, startDate: Day.today)
            store.saveRule(rule)
            let block = try XCTUnwrap(store.state.schedule.first)
            // Matches the GTK save-schedule mapping: occurrence is never sent.
            let draft = ScheduleDraftModel(id: block.id, title: block.title, day: Day.adding(3),
                startMinute: block.startMinute, duration: block.duration, ruleID: rule.id, exists: true)
            _ = LinuxSession(store: store).handle(.saveSchedule(draft))
            XCTAssertEqual(store.state.schedule.first { $0.id == block.id }?.occurrence, block.occurrence)
        }
    }

    @MainActor func testLinuxScheduleRejectsImpossibleDate() async throws {
        try withStore { store in
            let draft = ScheduleDraftModel(title: "Exam session", day: "2026-02-31")
            _ = LinuxSession(store: store).handle(.saveSchedule(draft))
            XCTAssertNotNil(draft.validationError)
            XCTAssertTrue(store.state.schedule.isEmpty)
        }
    }

    func testRhythmPayloadPreservesPipesAndMultilineNotes() {
        let notes = "Read A | compare B\n| Column | Value |\n"
        XCTAssertEqual(rhythmMetadata("2026-09-13||" + notes), ["2026-09-13", "", notes])
        XCTAssertEqual(rhythmMetadata("2026-09-13|2026-10-01|"), ["2026-09-13", "2026-10-01", ""])
    }

    func testScheduleAndRhythmDateValidation() {
        XCTAssertNil(ScheduleDraftModel(title: "Leap day", day: "2028-02-29").validationError)
        for invalid in ["2026-02-29", "2026-13-01", "2026-01-32", "not a date", "2026-9-1"] {
            XCTAssertNotNil(ScheduleDraftModel(title: "Event", day: invalid).validationError, invalid)
            XCTAssertNotNil(ScheduleDraftModel(title: "Event", repeatEnd: invalid).validationError, invalid)
            XCTAssertNotNil(RuleDraftModel(title: "Rhythm", startDate: invalid).validationError, invalid)
            XCTAssertNotNil(RuleDraftModel(title: "Rhythm", endDate: invalid).validationError, invalid)
        }
        XCTAssertNotNil(ScheduleDraftModel(title: "Repeat", day: "2026-09-13", repeatEnabled: true,
            repeatDays: [1], repeatEnd: "2026-09-12").validationError)
    }

    @MainActor func testPausingPreservesAnnotatedAssessmentsAndSchedules() async throws {
        try withStore { store in
            var assessmentRule = QuizRule(title: "Quiz", weekdays: Array(1...7), itemKind: .assessment, startDate: Day.today)
            var scheduleRule = QuizRule(title: "Study", weekdays: Array(1...7), itemKind: .schedule, startDate: Day.today)
            store.saveRule(assessmentRule)
            store.saveRule(scheduleRule)
            var assessment = try XCTUnwrap(store.state.assessments.first)
            var block = try XCTUnwrap(store.state.schedule.first)
            assessment.topics = "Exam outline"
            block.notes = "Bring textbook"
            store.save(assessment)
            store.save(block)
            assessmentRule.enabled = false
            scheduleRule.enabled = false
            store.saveRule(assessmentRule)
            store.saveRule(scheduleRule)
            XCTAssertEqual(store.state.assessments, [assessment])
            XCTAssertEqual(store.state.schedule, [block])
            let reopened = try Store(database: Database(url: store.location))
            XCTAssertEqual(reopened.state.assessments, [assessment])
            XCTAssertEqual(reopened.state.schedule, [block])
        }
    }

    @MainActor func testListNoteAndLinkedEntryProtectOccurrenceIDs() async throws {
        try withStore { store in
            var rule = QuizRule(title: "Quiz", weekdays: Array(1...7), itemKind: .assessment, startDate: Day.today)
            store.saveRule(rule)
            let first = store.state.assessments[0]
            let second = store.state.assessments[1]
            store.save(Course(name: "Notes", notes: [ListNote(markdown: JournalLink.assessment(first.id).embedToken)]))
            store.save(JournalEntry(day: Day.today, title: second.title, link: .assessment(second.id)))
            rule.enabled = false
            store.saveRule(rule)
            XCTAssertEqual(Set(store.state.assessments.map(\.id)), Set([first.id, second.id]))
        }
    }
}
