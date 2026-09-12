import XCTest
@testable import OpusCore

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
    @MainActor func testRecurrenceSkipsAndMovesSurviveRegeneration() async throws {
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
    @MainActor func testAssessmentRhythmCreateUpdateAndDelete() async throws {
        let store = try Store(database: database())
        let course = Course(name: "Example list")
        store.save(course)
        var rule = QuizRule(
            courseID: course.id,
            title: "Chapter quiz",
            weekdays: Array(1...7),
            itemKind: .assessment,
            startDate: Day.today,
            endDate: Day.adding(2),
            notes: "Chapter 4"
        )
        rule.assessmentsConfirmed = false

        store.saveRule(rule)
        XCTAssertEqual(store.state.assessments.count, 3)
        XCTAssertTrue(store.state.tasks.isEmpty)
        XCTAssertTrue(store.state.assessments.allSatisfy {
            $0.courseID == course.id && $0.title == "Chapter quiz" &&
                $0.confirmed && $0.topics == "Chapter 4" && $0.ruleID == rule.id
        })

        rule.title = "Chapter exam"
        rule.notes = "Chapters 4–5"
        rule.assessmentsConfirmed = true
        store.saveRule(rule)
        XCTAssertEqual(store.state.assessments.count, 3)
        XCTAssertTrue(store.state.assessments.allSatisfy {
            $0.title == "Chapter exam" && $0.confirmed && $0.topics == "Chapters 4–5"
        })

        store.deleteRule(rule.id)
        XCTAssertFalse(store.state.rules.contains { $0.id == rule.id })
        XCTAssertFalse(store.state.assessments.contains { $0.ruleID == rule.id })
        store.undo()
        XCTAssertEqual(store.state.assessments.filter { $0.ruleID == rule.id }.count, 3)
    }
    @MainActor func testRemoveListPreservesWorkAndUndoRestoresIt() async throws {
        let store = try Store(database: database())
        let course = Course(name: "Example list")
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
    @MainActor func testProgressCompletionCorrectionAndUndo() async throws {
        let store = try Store(database: database())
        let task = StudyTask(title: "Notes", kind: .progress, start: 10, target: 20, current: 9)
        store.save(task)
        store.record(task, value: 20, note: "Done")
        XCTAssertFalse(store.state.tasks[0].completed)
        store.record(store.state.tasks[0], value: 18, note: "Correction")
        XCTAssertFalse(store.state.tasks[0].completed)
        XCTAssertEqual(store.state.activities.count, 2)
        store.undo()
        XCTAssertEqual(store.state.tasks[0].current, 20)
        XCTAssertEqual(store.state.activities.count, 1)
    }
    @MainActor func testCompletedProgressNormalizesWithoutLosingPosition() async throws {
        let database = try database()
        var state = Snapshot()
        state.tasks = [StudyTask(title: "Book", kind: .progress, completed: true, start: 10, target: 20, current: 20)]
        try database.save(state)
        let store = try Store(database: database)
        XCTAssertFalse(store.state.tasks[0].completed)
        XCTAssertEqual(store.state.tasks[0].current, 20)
        XCTAssertFalse(try database.load().tasks[0].completed)
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
    @MainActor func testCalendarDropPersistsMoveAndUndo() async throws {
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
        XCTAssertNil(store.state.tasks.first?.planned)
        XCTAssertEqual(store.state.tasks.first?.calendarDay, "2026-09-14")
        XCTAssertFalse(store.reschedule("arbitrary text", to: "2026-09-14"))
    }
    @MainActor func testCalendarDayPrefersDueAndRescheduleClearsPlanned() async throws {
        let store = try Store(database: Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusDay-" + UUID().uuidString).appendingPathComponent("test.sqlite")))
        var task = StudyTask(title: "Essay", planned: "2026-09-09", due: "2026-09-10")
        store.save(task)
        XCTAssertEqual(store.state.tasks[0].calendarDay, "2026-09-10")
        task = store.state.tasks[0]
        task.moveCalendarDay(to: "2026-09-11")
        store.save(task)
        XCTAssertEqual(store.state.tasks[0].due, "2026-09-11")
        XCTAssertNil(store.state.tasks[0].planned)
        XCTAssertEqual(store.state.tasks[0].calendarDay, "2026-09-11")
        var plannedOnly = StudyTask(title: "Inbox", planned: "2026-09-08")
        store.save(plannedOnly)
        plannedOnly = store.state.tasks.first { $0.title == "Inbox" }!
        plannedOnly.moveCalendarDay(to: "2026-09-12")
        store.save(plannedOnly)
        XCTAssertEqual(store.state.tasks.first { $0.title == "Inbox" }?.planned, "2026-09-12")
        XCTAssertNil(store.state.tasks.first { $0.title == "Inbox" }?.due)
    }
    @MainActor func testDeleteArchivedTasksClearsCompletedOnly() async throws {
        let store = try Store(database: Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusArchive-" + UUID().uuidString).appendingPathComponent("test.sqlite")))
        store.save(StudyTask(title: "Done", completed: true))
        store.save(StudyTask(title: "Open"))
        store.deleteArchivedTasks()
        XCTAssertEqual(store.state.tasks.map(\.title), ["Open"])
        store.undo()
        XCTAssertEqual(Set(store.state.tasks.map(\.title)), Set(["Done", "Open"]))
    }
    @MainActor func testManualReorderingSurvivesReopening() async throws {
        let database = try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusOrder-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let tasks = [StudyTask(title: "A"), StudyTask(title: "B"), StudyTask(title: "C")]
        for task in tasks { store.save(task) }
        store.moveTask(tasks[2].id, before: tasks[0].id)
        XCTAssertEqual(try database.load().tasks.map(\.title), ["C", "A", "B"])
        store.undo()
        XCTAssertEqual(store.state.tasks.map(\.title), ["A", "B", "C"])
    }
    @MainActor func testAssessmentCreationAndUpdate() async throws {
        let store = try Store(database: Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusAssess-" + UUID().uuidString).appendingPathComponent("test.sqlite")))
        let course = Course(name: "Example list")
        store.save(course)
        let item = Assessment(courseID: course.id, title: "Unit test", day: "2026-09-15", confirmed: true, topics: "Ch. 4")
        store.save(item)
        XCTAssertEqual(store.state.assessments.count, 1)
        var edited = store.state.assessments[0]
        edited.title = "Unit exam"
        edited.confirmed = false
        store.save(edited)
        XCTAssertEqual(store.state.assessments[0].title, "Unit exam")
        XCTAssertTrue(store.state.assessments[0].confirmed)
        store.undo()
        XCTAssertEqual(store.state.assessments[0].title, "Unit test")
    }
}
