import Foundation
import XCTest
import OpusCore
@testable import OpusGTKSupport

final class InspectionRegressionTests: XCTestCase {
    @MainActor func testLinuxNotesSurviveReopening() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let store = try Store(database: Database(url: url))
        let session = LinuxSession(store: store)
        _ = session.handle(.saveWork(WorkDraftModel(title: "Essay", notes: "Keep this outline")))
        XCTAssertEqual(store.state.tasks.first?.notes, "Keep this outline")
        let reopened = try Store(database: Database(url: url))
        XCTAssertEqual(reopened.state.tasks.first?.notes, "Keep this outline")
    }

    @MainActor func testConvertingTaskToAssessmentRemovesOriginalTask() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let task = StudyTask(title: "Exam", due: Day.today)
        store.save(task)
        var draft = WorkDraftModel.from(task: task)
        draft.kind = .assessment
        _ = LinuxSession(store: store).handle(.saveWork(draft))
        XCTAssertEqual(store.state.assessments.count, 1)
        XCTAssertFalse(store.state.tasks.contains { $0.id == task.id })
    }

    @MainActor func testConversionUpdatesLinksPreservesRecurrenceAndUndoesAtomically() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Database(url: folder.appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let rule = QuizRule(title: "Read", weekdays: Array(1...7), itemKind: .task, startDate: Day.today)
        store.saveRule(rule)
        let task = try XCTUnwrap(store.state.tasks.first)
        store.record(task, value: nil, note: "Started")
        store.save(JournalEntry(day: Day.today, title: "Journal", markdown: JournalLink.task(task.id).embedToken))
        store.save(JournalEntry(day: Day.today, title: task.title, link: .task(task.id)))
        let before = store.state
        var draft = WorkDraftModel.from(task: task)
        draft.kind = .assessment
        let session = LinuxSession(store: store)
        _ = session.handle(.saveWork(draft))
        let assessment = try XCTUnwrap(store.state.assessments.first)
        XCTAssertEqual(assessment.ruleID, rule.id)
        XCTAssertEqual(assessment.occurrence, task.occurrence)
        XCTAssertTrue(store.state.activities.isEmpty)
        XCTAssertEqual(store.journalDocument(on: Day.today)?.markdown, JournalLink.assessment(task.id).embedToken)
        XCTAssertEqual(store.journalTaskEmbeds(on: Day.today).first?.link, .assessment(task.id))
        store.undo()
        XCTAssertEqual(store.state.tasks, before.tasks)
        XCTAssertEqual(store.state.activities, before.activities)
        XCTAssertEqual(store.state.journal, before.journal)
        _ = session.handle(.saveWork(draft))
        store.refreshOccurrences()
        XCTAssertFalse(store.state.tasks.contains { $0.id == task.id || ($0.ruleID == rule.id && $0.occurrence == task.occurrence) })
        var reverse = WorkDraftModel.from(assessment: try XCTUnwrap(store.state.assessments.first))
        reverse.kind = .task
        reverse.day = nil
        _ = session.handle(.saveWork(reverse))
        XCTAssertTrue(store.state.assessments.isEmpty)
        let converted = try XCTUnwrap(database.load().tasks.first { $0.id == task.id })
        XCTAssertNil(converted.due)
        XCTAssertEqual(converted.ruleID, rule.id)
        XCTAssertEqual(store.journalDocument(on: Day.today)?.markdown, JournalLink.task(task.id).embedToken)
    }

    @MainActor func testDeleteAllEventsIntentionallyKeepsHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let rule = QuizRule(title: "Daily", weekdays: Array(1...7), itemKind: .schedule, startDate: Day.adding(-1))
        store.saveRule(rule)
        let block = try XCTUnwrap(store.state.schedule.first { $0.day == Day.today })
        store.deleteSchedule(block, scope: .allEvents)
        XCTAssertEqual(Set(store.state.schedule.map(\.day)), Set([Day.adding(-1), Day.today]))
    }
}
