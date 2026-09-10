import XCTest
import CSQLite
@testable import Opus

final class RedesignTests: XCTestCase {
    func testPacingUsesInclusiveDaysAndActualPageRange() {
        var task = StudyTask(title: "Notes", kind: .progress, due: "2026-09-11", start: 17, target: 49, current: 25)
        XCTAssertEqual(task.pacing(on: "2026-09-09"), "Read through page 33 today · 8 pages/day over 3 days")
        XCTAssertEqual(task.pacing(on: "2026-09-11"), "Read through page 49 today · 24 pages/day over 1 day")
        XCTAssertEqual(task.pacing(on: "2026-09-12"), "Overdue · 24 pages left")
        task.due = nil
        XCTAssertEqual(task.pacing(on: "2026-09-09"), "Set a due date to plan your daily pace")
        task.current = 49
        XCTAssertNil(task.pacing(on: "2026-09-09"))
    }
    func testScheduleClickUsesQuarterHourAndLateNight() {
        XCTAssertEqual(ScheduleLayout.minute(at: 630), 630)
        XCTAssertEqual(ScheduleLayout.minute(at: 644), 630)
        XCTAssertEqual(ScheduleLayout.minute(at: 1439), 1425)
        XCTAssertEqual(ScheduleLayout.minute(at: -10), 0)
        XCTAssertEqual(ScheduleLayout.minute(at: 315, hourHeight: 30), 630)
    }
    func testTodayIncludesTomorrowWithoutRecurringBacklog() {
        let today = "2026-09-09"
        XCTAssertTrue(StudyTask(title: "Tomorrow", planned: "2026-09-10").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Due tomorrow", due: "2026-09-10").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Overdue", due: "2026-09-08").isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Later", planned: "2026-09-11").isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Past repeat", planned: "2026-09-08", ruleID: "r").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Next repeat", planned: "2026-09-10", ruleID: "r").isInToday(on: today))
    }
    func testClassTimesDecodeLegacyAndFollowWeekdays() throws {
        let legacy = try JSONDecoder().decode(Course.self, from: Data(#"{"id":"c","name":"Example A","color":"blue"}"#.utf8))
        XCTAssertNil(legacy.classBlock(on: "2026-09-09"))
        var course = legacy
        course.classStart = 465; course.classDuration = 50; course.classDays = [2,3,4,5,6]
        let copy = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertEqual(copy.classBlock(on: "2026-09-09")?.startMinute, 465)
        XCTAssertEqual(copy.classBlock(on: "2026-09-09")?.duration, 50)
        XCTAssertNil(copy.classBlock(on: "2026-09-12"))
        course.classStart = 600
        XCTAssertEqual(course.classBlock(on: "2026-09-09")?.startMinute, 600)
    }
    private func db() throws -> Database {
        try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusV3-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
    }
    @MainActor func testWeeklyQuizzesBecomeConfirmedOnce() throws {
        let database = try db()
        let rule = QuizRule(title: "Example recurrence")
        var state = Snapshot()
        state.rules = [rule]
        state.assessments = [Assessment(title: "Example recurrence", day: Day.today, ruleID: rule.id, occurrence: Day.today)]
        try database.save(state)
        let store = try Store(database: database)
        XCTAssertTrue(store.state.assessments.allSatisfy(\.confirmed))
        XCTAssertEqual(store.state.rules.first?.assessmentsConfirmed, true)
        var item = store.state.assessments[0]
        item.confirmed = false
        store.save(item)
        let reopened = try Store(database: database)
        XCTAssertFalse(try XCTUnwrap(reopened.state.assessments.first { $0.id == item.id }).confirmed)
    }
    func testLegacyRuleDecodesAsWeeklyAssessment() throws {
        let data = Data(#"{"id":"legacy","title":"Quiz","weekday":4,"enabled":true}"#.utf8)
        let rule = try JSONDecoder().decode(QuizRule.self, from: data)
        XCTAssertEqual(rule.kind, .assessment)
        XCTAssertEqual(rule.days, [4])
        XCTAssertTrue(rule.occurs(on: "2026-09-09"))
        XCTAssertFalse(rule.occurs(on: "2026-09-10"))
    }
    @MainActor func testCustomDaysGenerateTasksAndRespectEndDate() {
        var state = Snapshot()
        var rule = QuizRule(title: "Vocabulary", weekdays: [2,3,4], itemKind: .task, startDate: "2026-09-07", endDate: "2026-09-16", taskKind: .practice)
        state.rules = [rule]
        Store.generate(in: &state, today: "2026-09-07")
        XCTAssertEqual(state.tasks.compactMap(\.planned), ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-14", "2026-09-15", "2026-09-16"])
        XCTAssertTrue(state.assessments.isEmpty)
        Store.generate(in: &state, today: "2026-09-07")
        XCTAssertEqual(state.tasks.count, 6)
        rule.weekdays = Array(1...7); rule.endDate = "2026-09-11"
        var daily = Snapshot(); daily.rules = [rule]
        Store.generate(in: &daily, today: "2026-09-07")
        XCTAssertEqual(daily.tasks.count, 5)
    }
    func testEveryOtherWeekAnchorsAtStartWeek() {
        let rule = QuizRule(title: "Practice", weekdays: [2,4], intervalWeeks: 2, startDate: "2026-09-07")
        XCTAssertTrue(rule.occurs(on: "2026-09-07"))
        XCTAssertFalse(rule.occurs(on: "2026-09-14"))
        XCTAssertTrue(rule.occurs(on: "2026-09-21"))
        XCTAssertFalse(rule.occurs(on: "2026-09-02"))
    }
    @MainActor func testPausePreservesEditedScheduleAndCompletedTasks() throws {
        let store = try Store(database: db())
        var rule = QuizRule(title: "Study", weekdays: Array(1...7), itemKind: .schedule, startDate: Day.today, startMinute: 540, duration: 60)
        store.saveRule(rule)
        var edited = try XCTUnwrap(store.state.schedule.first)
        edited.startMinute = 555; store.save(edited)
        rule.enabled = false; store.saveRule(rule)
        XCTAssertEqual(store.state.schedule.count, 1)
        XCTAssertEqual(store.state.schedule.first?.startMinute, 555)
        var tasks = QuizRule(title: "Review", weekdays: Array(1...7), itemKind: .task, startDate: Day.today)
        store.saveRule(tasks)
        var completed = try XCTUnwrap(store.state.tasks.first)
        completed.completed = true; store.save(completed)
        tasks.enabled = false; store.saveRule(tasks)
        XCTAssertEqual(store.state.tasks.count, 1)
        XCTAssertTrue(store.state.tasks[0].completed)
    }
    func testMigrationAddsScheduleWithoutLosingExistingData() throws {
        let database = try db()
        var state = Snapshot(); state.tasks = [StudyTask(title: "Existing notes", kind: .progress, start: 17, target: 49, current: 25)]
        try database.save(state)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE schedule; PRAGMA user_version=1;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let migrated = try Database(url: database.url)
        var restored = try migrated.load()
        XCTAssertEqual(restored.tasks, state.tasks)
        restored.schedule = [ScheduleBlock(title: "Example list", day: "2026-09-09", startMinute: 480, duration: 50)]
        try migrated.save(restored)
        XCTAssertEqual(try Database(url: database.url).load().schedule, restored.schedule)
    }
    func testScheduleOverlapsUseSeparateColumns() {
        let a = ScheduleBlock(title: "A", startMinute: 540, duration: 60)
        let b = ScheduleBlock(title: "B", startMinute: 570, duration: 60)
        let c = ScheduleBlock(title: "C", startMinute: 630, duration: 30)
        let placements = ScheduleLayout.placements([c,b,a])
        XCTAssertEqual(placements.map(\.columns), [2,2,1])
        XCTAssertNotEqual(placements[0].column, placements[1].column)
        XCTAssertEqual(placements[2].column, 0)
    }
    func testNotesDraftMergesWithLiveProgress() {
        let original = StudyTask(title: "Notes", kind: .progress, current: 3)
        var draft = original; draft.notes = "Keep this edit"
        var live = original; live.current = 10
        let merged = StudyTask.merging(draft: draft, baseline: original, latest: live)
        XCTAssertEqual(merged.notes, "Keep this edit")
        XCTAssertEqual(merged.current, 10)
    }
    @MainActor func testDirectProgressClampsAndDoesNotDuplicateEntries() throws {
        let store = try Store(database: db())
        let task = StudyTask(title: "Notes", kind: .progress, start: 17, target: 49, current: 25)
        store.save(task)
        store.updateProgress(task.id, to: 26)
        store.updateProgress(task.id, to: 26)
        XCTAssertEqual(store.state.activities.count, 1)
        store.updateProgress(task.id, to: 999)
        XCTAssertEqual(store.state.tasks[0].current, 49)
        XCTAssertTrue(store.state.tasks[0].completed)
        store.updateProgress(task.id, to: 0)
        XCTAssertEqual(store.state.tasks[0].current, 16)
        XCTAssertFalse(store.state.tasks[0].completed)
    }
}
