import XCTest
@testable import Opus

final class StorageTests: XCTestCase {
    func database() throws -> Database {
        try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusTests-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
    }
    func testPersistenceAndCascadeData() throws {
        let db = try database()
        let course = Course(name: "Example's text 📚")
        let task = StudyTask(courseID: course.id, title: "Chapter 'one'", notes: "line one\nline two", kind: .progress, start: 206, target: 235, current: 217)
        var snapshot = Snapshot()
        snapshot.courses = [course]
        snapshot.tasks = [task]
        snapshot.activities = [Activity(taskID: task.id, note: "Finished", previous: 205, value: 217)]
        snapshot.setupComplete = true
        try db.save(snapshot)
        let reopened = try Database(url: db.url).load()
        XCTAssertEqual(reopened.tasks, snapshot.tasks)
        XCTAssertEqual(reopened.activities, snapshot.activities)
        XCTAssertEqual(reopened.courses, snapshot.courses)
        XCTAssertTrue(reopened.setupComplete)
        XCTAssertEqual(task.fraction, 0.4, accuracy: 0.001)
        XCTAssertEqual(task.progressLabel, "12 of 30 pages")
    }
    func testFailedWriteRollsBack() throws {
        let db = try database()
        var snapshot = Snapshot()
        snapshot.tasks = [StudyTask(title: "Keep me")]
        try db.save(snapshot)
        var invalid = snapshot
        invalid.tasks.append(StudyTask(courseID: "missing", title: "Invalid reference"))
        XCTAssertThrowsError(try db.save(invalid))
        XCTAssertEqual(try db.load().tasks, snapshot.tasks)
    }
    @MainActor func testRecurrenceSkipsAndMovesSurviveRegeneration() throws {
        let store = try Store(database: database())
        let rule = QuizRule(title: "Example review", weekday: 4)
        store.saveRule(rule)
        XCTAssertEqual(store.state.assessments.count, 8)
        let skipped = try XCTUnwrap(store.state.assessments.first)
        store.change { $0.assessments.removeAll { $0.id == skipped.id } }
        var moved = try XCTUnwrap(store.state.assessments.first)
        moved.day = Day.adding(1, to: moved.day)
        store.save(moved)
        store.refreshOccurrences()
        XCTAssertEqual(store.state.assessments.count, 7)
        XCTAssertEqual(store.state.assessments.first { $0.id == moved.id }?.day, moved.day)
        XCTAssertFalse(store.state.assessments.contains { $0.occurrence == skipped.occurrence })
        var edited = rule
        edited.title = "Updated quiz"
        store.saveRule(edited)
        XCTAssertEqual(store.state.assessments.count, 7)
        XCTAssertTrue(store.state.assessments.contains { $0.id == moved.id })
    }
    @MainActor func testRemoveListPreservesWorkAndUndoRestoresIt() throws {
        let store = try Store(database: database())
        let course = Course(name: "Example F")
        store.save(course)
        let task = StudyTask(courseID: course.id, title: "Notes")
        store.save(task)
        store.deleteCourse(course.id)
        XCTAssertNil(store.state.tasks.first?.courseID)
        XCTAssertEqual(store.state.tasks.first?.title, "Notes")
        store.undo()
        XCTAssertEqual(store.state.courses, [course])
        XCTAssertEqual(store.state.tasks.first?.courseID, course.id)
    }
    @MainActor func testProgressCompletionCorrectionAndUndo() throws {
        let store = try Store(database: database())
        let task = StudyTask(title: "Notes", kind: .progress, start: 10, target: 20, current: 9)
        store.save(task)
        store.record(task, value: 20, note: "Done")
        XCTAssertTrue(store.state.tasks[0].completed)
        store.record(store.state.tasks[0], value: 18, note: "Correction")
        XCTAssertFalse(store.state.tasks[0].completed)
        XCTAssertEqual(store.state.activities.count, 2)
        store.undo()
        XCTAssertEqual(store.state.tasks[0].current, 20)
        XCTAssertEqual(store.state.activities.count, 1)
    }
    func testCalendarDayRoundtrip() {
        for day in ["2026-03-08", "2026-11-01", "2028-02-29"] { XCTAssertEqual(Day.string(Day.date(day)), day) }
        XCTAssertEqual(Day.adding(1, to: "2026-12-31"), "2027-01-01")
    }
}

final class CalendarInteractionTests: XCTestCase {
    func testMonthGridIncludesEveryDateAndWholeWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        for month in ["2026-02-15", "2026-08-15", "2026-12-15", "2028-02-15"] {
            let date = Day.date(month)
            let days = CalendarLayout.days(containing: date, week: false, calendar: calendar)
            XCTAssertEqual(days.count % 7, 0)
            XCTAssertEqual(calendar.component(.weekday, from: Day.date(days[0])), 2)
            XCTAssertEqual(Set(days).count, days.count)
            let monthNumber = calendar.component(.month, from: date)
            XCTAssertEqual(days.filter { calendar.component(.month, from: Day.date($0)) == monthNumber }.count, calendar.range(of: .day, in: .month, for: date)?.count)
        }
    }
    func testWeekGridCrossesYearBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let days = CalendarLayout.days(containing: Day.date("2027-01-01"), week: true, calendar: calendar)
        XCTAssertEqual(days, ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    }
    @MainActor func testCalendarDropPersistsMoveAndUndo() throws {
        let database = try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusDrop-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let assessment = Assessment(title: "Test", day: "2026-09-10")
        store.save(assessment)
        XCTAssertTrue(store.reschedule("assessment:" + assessment.id, to: "2026-09-12"))
        XCTAssertEqual(try database.load().assessments.first?.day, "2026-09-12")
        store.undo()
        XCTAssertEqual(store.state.assessments.first?.day, "2026-09-10")
        let task = StudyTask(title: "Notes", planned: "2026-09-08", due: "2026-09-10")
        store.save(task)
        XCTAssertTrue(store.reschedule("task:" + task.id, to: "2026-09-14"))
        XCTAssertEqual(store.state.tasks.first?.due, "2026-09-14")
        XCTAssertEqual(store.state.tasks.first?.planned, "2026-09-08")
        XCTAssertFalse(store.reschedule("arbitrary text", to: "2026-09-14"))
    }
    @MainActor func testManualReorderingSurvivesReopening() throws {
        let database = try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusOrder-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let tasks = [StudyTask(title: "A"), StudyTask(title: "B"), StudyTask(title: "C")]
        for task in tasks { store.save(task) }
        store.moveTask(tasks[2].id, before: tasks[0].id)
        XCTAssertEqual(try database.load().tasks.map(\.title), ["C", "A", "B"])
        store.undo()
        XCTAssertEqual(store.state.tasks.map(\.title), ["A", "B", "C"])
    }
}
