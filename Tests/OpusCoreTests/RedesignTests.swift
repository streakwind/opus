import XCTest
import CSQLite
@testable import OpusCore

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
        task.current = 50
        XCTAssertNil(task.pacing(on: "2026-09-09"))
    }
    func testProgressStartsUnreadAndCompletesPastLastPage() {
        let zero = StudyTask(title: "PDF", kind: .progress, start: 0, target: 100)
        XCTAssertEqual(zero.current, 0)
        XCTAssertEqual(zero.pagesRead, 0)
        XCTAssertEqual(zero.pagesTotal, 101)
        XCTAssertEqual(zero.progressLabel, "0 of 101 pages")
        XCTAssertFalse(zero.isProgressComplete)
        XCTAssertEqual(zero.clampedProgress(-1), 0)
        XCTAssertEqual(zero.clampedProgress(10), 10)
        XCTAssertEqual(zero.clampedProgress(101), 101)

        var book = StudyTask(title: "Book", kind: .progress, start: 1, target: 30)
        XCTAssertEqual(book.current, 1)
        XCTAssertEqual(book.pagesRead, 0)
        XCTAssertEqual(book.progressLabel, "0 of 30 pages")
        XCTAssertEqual(book.clampedProgress(0), 1)
        book.current = 30
        XCTAssertEqual(book.progressLabel, "30 of 30 pages")
        XCTAssertFalse(book.isProgressComplete)
        book.current = 31
        XCTAssertEqual(book.progressLabel, "30 of 30 pages")
        XCTAssertTrue(book.isProgressComplete)
        XCTAssertEqual(book.clampedProgress(99), 31)

        let mid = StudyTask(title: "Notes", kind: .progress, start: 3, target: 30)
        XCTAssertEqual(mid.current, 3)
        XCTAssertEqual(mid.pagesRead, 0)
        XCTAssertEqual(mid.clampedProgress(1), 3)

        var progressed = zero
        progressed.current = 10
        XCTAssertEqual(progressed.pagesRead, 11)
        XCTAssertEqual(StudyTask(title: "Notes", kind: .progress, start: 17, target: 49, current: 25).pagesRead, 9)
    }
    func testScheduleClickUsesQuarterHourAndLateNight() {
        XCTAssertEqual(ScheduleLayout.minute(at: 630), 630)
        XCTAssertEqual(ScheduleLayout.minute(at: 644), 630)
        XCTAssertEqual(ScheduleLayout.minute(at: 1439), 1425)
        XCTAssertEqual(ScheduleLayout.minute(at: -10), 0)
        XCTAssertEqual(ScheduleLayout.minute(at: 315, hourHeight: 30), 630)
    }
    func testScheduleDragRangeSnapsInBothDirectionsAndAllowsMinimumBlock() {
        let forward = ScheduleLayout.range(startY: 482, endY: 541)
        XCTAssertEqual(forward.start, 480)
        XCTAssertEqual(forward.duration, 60)
        let reverse = ScheduleLayout.range(startY: 541, endY: 482)
        XCTAssertEqual(reverse.start, 480)
        XCTAssertEqual(reverse.duration, 60)
        XCTAssertEqual(ScheduleLayout.range(startY: 482, endY: 483).duration, 15)
        let late = ScheduleLayout.block(day: "2026-09-09", startY: 1438, endY: 1500)
        XCTAssertEqual(late.startMinute + late.duration, 1440)
    }
    func testTodayUsesSevenDayDeadlinesAndAllUnfinishedProgress() {
        let today = "2026-09-09"
        XCTAssertTrue(StudyTask(title: "Due tomorrow", due: "2026-09-10").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Due in a week", due: "2026-09-16").isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Due later", due: "2026-09-17").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Overdue", due: "2026-09-08").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "No deadline").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Planned only", planned: "2026-09-10").isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Completed", due: "2026-09-10", completed: true).isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Past repeat", due: "2026-09-08", ruleID: "r").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Next repeat", due: "2026-09-16", ruleID: "r").isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Later repeat", due: "2026-09-17", ruleID: "r").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Book", kind: .progress, due: "2027-01-01", start: 1, target: 30, current: 10).isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Undated book", kind: .progress, start: 1, target: 30, current: 10).isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Undated rhythm book", kind: .progress, start: 1, target: 30, current: 10, ruleID: "r").isInToday(on: today))
        XCTAssertTrue(StudyTask(title: "Last page", kind: .progress, start: 1, target: 30, current: 30).isInToday(on: today))
        XCTAssertFalse(StudyTask(title: "Finished book", kind: .progress, start: 1, target: 30, current: 31).isInToday(on: today))
    }
    @MainActor func testGenerationRetainsYesterdayTaskButNotPastCalendarEvents() async {
        let today = "2026-09-09"
        let yesterday = "2026-09-08"
        var tasks = Snapshot()
        tasks.rules = [QuizRule(title: "Daily review", weekdays: Array(1...7), itemKind: .task, startDate: yesterday)]
        Store.generate(in: &tasks, today: today)
        XCTAssertTrue(tasks.tasks.contains { $0.due == yesterday && $0.occurrence == yesterday && $0.planned == nil })

        var assessments = Snapshot()
        assessments.rules = [QuizRule(title: "Daily quiz", weekdays: Array(1...7), itemKind: .assessment, startDate: yesterday)]
        Store.generate(in: &assessments, today: today)
        XCTAssertFalse(assessments.assessments.contains { $0.day == yesterday })

        var schedule = Snapshot()
        let twoWeeksAgo = Day.adding(-14, to: today)
        schedule.rules = [QuizRule(title: "Practice", weekdays: Array(1...7), itemKind: .schedule, startDate: twoWeeksAgo)]
        Store.generate(in: &schedule, today: today)
        XCTAssertTrue(schedule.schedule.contains { $0.day == yesterday })
        XCTAssertTrue(schedule.schedule.contains { $0.day == twoWeeksAgo })
    }
    func testClassTimesDecodeLegacyAndFollowWeekdays() throws {
        let legacy = try JSONDecoder().decode(Course.self, from: Data(#"{"id":"c","name":"Example list","color":"blue"}"#.utf8))
        XCTAssertNil(legacy.classBlock(on: "2026-09-09"))
        XCTAssertFalse(legacy.isListOnly)
        var course = legacy
        course.classStart = 465; course.classDuration = 50; course.classDays = [2,3,4,5,6]
        let copy = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertEqual(copy.classBlock(on: "2026-09-09")?.startMinute, 465)
        XCTAssertEqual(copy.classBlock(on: "2026-09-09")?.duration, 50)
        XCTAssertNil(copy.classBlock(on: "2026-09-12"))
        course.classStart = 600
        XCTAssertEqual(course.classBlock(on: "2026-09-09")?.startMinute, 600)
    }
    func testMultipleClassTimesHaveStableDistinctBlocksAndLegacyMirror() throws {
        var course = Course(name: "Physics")
        course.classTimes = [
            ClassTime(id: "morning", startMinute: 480, endMinute: 530, days: [4]),
            ClassTime(id: "lab", startMinute: 780, endMinute: 900, days: [4])
        ]
        course.syncLegacyClassTime()
        let blocks = course.classBlocks(on: "2026-09-09")
        XCTAssertEqual(blocks.map(\.startMinute), [480, 780])
        XCTAssertEqual(Set(blocks.map(\.id)).count, 2)
        XCTAssertEqual(course.classStart, 480)
        XCTAssertEqual(course.classDuration, 50)
        let copy = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertEqual(copy.resolvedClassTimes, course.classTimes)
    }
    func testListOnlyCoursesStayOffTodayInboxAndCalendar() throws {
        let hidden = Course(name: "Personal", listOnly: true)
        let listed = Course(name: "Bio")
        XCTAssertTrue(hidden.isListOnly)
        XCTAssertFalse(listed.isListOnly)
        XCTAssertNil(try JSONDecoder().decode(
            Course.self,
            from: Data(#"{"id":"c","name":"Example list","color":"blue"}"#.utf8)
        ).listOnly)
        let encoded = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(hidden))
        XCTAssertTrue(encoded.isListOnly)
        var state = Snapshot(courses: [hidden, listed])
        state.tasks = [
            StudyTask(courseID: hidden.id, title: "Secret", due: Day.today),
            StudyTask(courseID: listed.id, title: "Essay", due: Day.today),
            StudyTask(title: "Loose", due: Day.today)
        ]
        state.assessments = [
            Assessment(courseID: hidden.id, title: "Private exam", day: Day.today),
            Assessment(courseID: listed.id, title: "Quiz", day: Day.today)
        ]
        XCTAssertFalse(state.showsInOverview(hidden.id))
        XCTAssertTrue(state.showsInOverview(listed.id))
        XCTAssertTrue(state.showsInOverview(nil))
    }
    @MainActor func testFreshInstallAndSetupNeverSeedUserData() async throws {
        let database = try db()
        let store = try Store(database: database)
        store.setup()
        let reopened = try Store(database: database)
        XCTAssertTrue(reopened.state.setupComplete)
        XCTAssertTrue(reopened.state.courses.isEmpty)
        XCTAssertTrue(reopened.state.rules.isEmpty)
        XCTAssertTrue(reopened.state.tasks.isEmpty)
        XCTAssertTrue(reopened.state.assessments.isEmpty)
        XCTAssertTrue(reopened.state.schedule.isEmpty)
    }
    private func db() throws -> Database {
        try Database(url: FileManager.default.temporaryDirectory.appendingPathComponent("OpusV3-" + UUID().uuidString).appendingPathComponent("test.sqlite"))
    }
    @MainActor func testAssessmentsAreAlwaysConfirmed() async throws {
        let database = try db()
        let rule = QuizRule(title: "Example review", assessmentsConfirmed: false)
        var state = Snapshot()
        state.rules = [rule]
        state.assessments = [Assessment(title: "Example review", day: Day.today, confirmed: false, ruleID: rule.id, occurrence: Day.today)]
        try database.save(state)
        let store = try Store(database: database)
        XCTAssertTrue(store.state.rules.first?.confirmsAssessments == true)
        var item = store.state.assessments[0]
        item.confirmed = false
        store.save(item)
        let reopened = try Store(database: database)
        XCTAssertTrue(try XCTUnwrap(reopened.state.assessments.first { $0.id == item.id }).confirmed)
    }
    func testLegacyRuleDecodesAsWeeklyAssessment() throws {
        let data = Data(#"{"id":"legacy","title":"Quiz","weekday":4,"enabled":true}"#.utf8)
        let rule = try JSONDecoder().decode(QuizRule.self, from: data)
        XCTAssertEqual(rule.kind, .assessment)
        XCTAssertEqual(rule.days, [4])
        XCTAssertTrue(rule.occurs(on: "2026-09-09"))
        XCTAssertFalse(rule.occurs(on: "2026-09-10"))
    }
    func testRhythmUsesSharedWorkKinds() {
        var rule = QuizRule(title: "Review", itemKind: .task)
        XCTAssertEqual(rule.workKind, .task)
        rule.workKind = .assessment
        XCTAssertEqual(rule.kind, .assessment)
        XCTAssertEqual(rule.workKind, .assessment)
        rule.workKind = .progress
        XCTAssertEqual(rule.kind, .task)
        XCTAssertEqual(rule.taskKind, .progress)
        XCTAssertEqual(rule.workKind, .progress)
        rule.workKind = .task
        XCTAssertEqual(rule.kind, .task)
        XCTAssertEqual(rule.taskKind, .checkbox)
    }
    @MainActor func testProgressRhythmGeneratesConfiguredRangeWithoutLegacyDetails() async {
        var state = Snapshot()
        let rule = QuizRule(
            title: "Read",
            weekdays: Array(1...7),
            itemKind: .task,
            startDate: "2026-09-07",
            endDate: "2026-09-07",
            taskKind: .progress,
            startCount: 17,
            targetCount: 49,
            notes: "Chapter 3"
        )
        state.rules = [rule]
        Store.generate(in: &state, today: "2026-09-07")
        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.tasks[0].kind, .progress)
        XCTAssertEqual(state.tasks[0].start, 17)
        XCTAssertEqual(state.tasks[0].target, 49)
        XCTAssertEqual(state.tasks[0].current, 17)
        XCTAssertEqual(state.tasks[0].notes, "")
        var zero = Snapshot()
        zero.rules = [QuizRule(title: "Zero", weekdays: Array(1...7), itemKind: .task, startDate: "2026-09-07", endDate: "2026-09-07", taskKind: .progress, startCount: 0, targetCount: 20)]
        Store.generate(in: &zero, today: "2026-09-07")
        XCTAssertEqual(zero.tasks[0].start, 0)
        XCTAssertEqual(zero.tasks[0].current, 0)
        XCTAssertEqual(zero.tasks[0].pagesRead, 0)
    }
    @MainActor func testCustomDaysGenerateTasksAndRespectEndDate() async {
        var state = Snapshot()
        var rule = QuizRule(title: "Vocabulary", weekdays: [2,3,4], itemKind: .task, startDate: "2026-09-07", endDate: "2026-09-16", taskKind: .practice)
        state.rules = [rule]
        Store.generate(in: &state, today: "2026-09-07")
        XCTAssertEqual(state.tasks.compactMap(\.due), ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-14", "2026-09-15", "2026-09-16"])
        XCTAssertTrue(state.tasks.allSatisfy { $0.planned == nil && $0.due == $0.occurrence })
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
    @MainActor func testPausePreservesEditedScheduleAndCompletedTasks() async throws {
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
    @MainActor func testRecurringScheduleDeletionScopes() async throws {
        let store = try Store(database: db())
        let rule = QuizRule(title: "Practice", weekdays: Array(1...7), itemKind: .schedule, startDate: Day.today)
        store.saveRule(rule)
        let originalCount = store.state.schedule.count
        let one = try XCTUnwrap(store.state.schedule.first)
        store.deleteSchedule(one, scope: .thisEvent)
        store.refreshOccurrences()
        XCTAssertEqual(store.state.schedule.count, originalCount - 1)
        XCTAssertFalse(store.state.schedule.contains { $0.id == one.id })

        let boundaryItem = try XCTUnwrap(store.state.schedule.dropFirst(2).first)
        let boundary = boundaryItem.occurrence ?? boundaryItem.day
        store.deleteSchedule(boundaryItem, scope: .thisAndFollowing)
        XCTAssertTrue(store.state.schedule.filter { $0.ruleID == rule.id }.allSatisfy { ($0.occurrence ?? $0.day) < boundary })
        XCTAssertEqual(store.state.rules.first { $0.id == rule.id }?.endDate, Day.adding(-1, to: boundary))

        let remaining = try XCTUnwrap(store.state.schedule.first { $0.ruleID == rule.id })
        store.deleteSchedule(remaining, scope: .allEvents)
        XCTAssertFalse(store.state.rules.contains { $0.id == rule.id })
        XCTAssertFalse(store.state.schedule.contains { $0.ruleID == rule.id })
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
    func testAllDayScheduleRoundTripsAndLegacyEventsStayTimed() throws {
        let allDay = ScheduleBlock(title: "Deadline", day: "2026-09-12", allDay: true)
        let copy = try JSONDecoder().decode(ScheduleBlock.self, from: JSONEncoder().encode(allDay))
        XCTAssertTrue(copy.isAllDay)
        let legacy = try JSONDecoder().decode(
            ScheduleBlock.self,
            from: Data(#"{"id":"old","title":"Class","day":"2026-09-12","startMinute":540,"duration":60,"notes":""}"#.utf8)
        )
        XCTAssertFalse(legacy.isAllDay)
    }
    func testScheduleTopRowContainsWorkWithoutAClassThatDay() {
        let day = "2026-09-12"
        let timed = Course(name: "Physics", classTimes: [ClassTime(startMinute: 540, endMinute: 600, days: [7])])
        let untimed = Course(name: "Independent study")
        var state = Snapshot()
        state.courses = [timed, untimed]
        state.tasks = [
            StudyTask(title: "Inbox task", due: day),
            StudyTask(courseID: timed.id, title: "Class task", due: day),
            StudyTask(courseID: untimed.id, title: "Untimed task", due: day)
        ]
        state.assessments = [
            Assessment(title: "Inbox quiz", day: day),
            Assessment(courseID: timed.id, title: "Class quiz", day: day),
            Assessment(courseID: untimed.id, title: "Untimed quiz", day: day)
        ]
        state.schedule = [
            ScheduleBlock(title: "Inbox event", day: day, allDay: true),
            ScheduleBlock(courseID: timed.id, title: "Class event", day: day, allDay: true),
            ScheduleBlock(courseID: untimed.id, title: "Untimed event", day: day, allDay: true),
            ScheduleBlock(title: "Timed event", day: day)
        ]

        XCTAssertEqual(ScheduleWork.untimedTasks(on: day, in: state).map(\.title), ["Inbox task", "Untimed task"])
        XCTAssertEqual(ScheduleWork.untimedAssessments(on: day, in: state).map(\.title), ["Inbox quiz", "Untimed quiz"])
        XCTAssertEqual(ScheduleWork.untimedEvents(on: day, in: state).map(\.title), ["Inbox event", "Untimed event"])
        XCTAssertEqual(ScheduleWork.listedEvents(courseID: timed.id, on: day, in: state).map(\.title), ["Class event"])
    }
    func testJournalEmbedOptionsKeepOnlyTheNextRhythmOccurrence() {
        let rule = "weekly"
        var state = Snapshot()
        state.tasks = [
            StudyTask(title: "Review", due: "2026-09-10", ruleID: rule, occurrence: "2026-09-10"),
            StudyTask(title: "Review", due: "2026-09-17", ruleID: rule, occurrence: "2026-09-17"),
            StudyTask(title: "Essay", due: "2026-09-12")
        ]
        state.assessments = [
            Assessment(title: "Quiz", day: "2026-09-11", ruleID: rule, occurrence: "2026-09-11"),
            Assessment(title: "Quiz", day: "2026-09-18", ruleID: rule, occurrence: "2026-09-18"),
            Assessment(title: "Lab", day: "2026-09-14")
        ]
        let options = JournalWork.embedOptions(in: state, from: "2026-09-09")
        XCTAssertEqual(options.filter { $0.title == "Review" }.count, 1)
        XCTAssertEqual(options.filter { $0.title == "Quiz" }.count, 1)
        XCTAssertEqual(options.map(\.title), ["Review", "Essay", "Quiz", "Lab"])
        XCTAssertEqual(options.first { $0.title == "Quiz" }?.link, .assessment(state.assessments[0].id))
    }
    func testJournalMarkdownPlacesCarriedEmbedsAndKeepsCommentsSeparate() {
        let task = JournalLink.task("essay")
        let placed = JournalMarkdown.placingCarriedEmbeds(in: "Morning notes", links: [task])
        XCTAssertTrue(placed.hasPrefix(task.embedToken))
        XCTAssertTrue(placed.contains("Morning notes"))
        XCTAssertEqual(JournalMarkdown.placingCarriedEmbeds(in: placed, links: [task]), placed)

        let inserted = JournalMarkdown.inserting(task.embedToken, into: "Before after", at: 6)
        XCTAssertEqual(JournalMarkdown.blocks(from: inserted).compactMap { block -> String? in
            if case .embed(let link) = block { return link.token }
            return nil
        }, [task.token])
        XCTAssertEqual(JournalMarkdown.removing(task.embedToken, from: placed).contains(task.embedToken), false)
        let onlyEmbed = JournalMarkdown.blocks(from: task.embedToken)
        XCTAssertEqual(onlyEmbed.count, 3)
        guard case .text(let before) = onlyEmbed[0], case .embed = onlyEmbed[1], case .text(let after) = onlyEmbed[2] else {
            return XCTFail("Embeds should keep editable text above and below")
        }
        XCTAssertTrue(before.isEmpty)
        XCTAssertTrue(after.isEmpty)
    }
    func testCourseWorkSeparatesProgressAndCollapsesRhythms() {
        let course = Course(name: "Example list")
        let rule = "weekly"
        var state = Snapshot()
        state.assessments = [
            Assessment(courseID: course.id, title: "Quiz", day: "2026-09-10", ruleID: rule),
            Assessment(courseID: course.id, title: "Quiz", day: "2026-09-17", ruleID: rule),
            Assessment(courseID: course.id, title: "Lab", day: "2026-09-12")
        ]
        state.tasks = [
            StudyTask(courseID: course.id, title: "Review", due: "2026-09-10", ruleID: rule),
            StudyTask(courseID: course.id, title: "Review", due: "2026-09-17", ruleID: rule),
            StudyTask(courseID: course.id, title: "Chapter", kind: .progress, due: "2026-09-12")
        ]
        XCTAssertEqual(CourseWork.assessments(courseID: course.id, from: "2026-09-09", in: state).count, 2)
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-09", in: state, progress: false).count, 1)
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-09", in: state, progress: true).count, 1)
    }
    func testProgressAppearsOnlyOnDueCalendarDay() {
        let course = Course(name: "English")
        var state = Snapshot()
        state.tasks = [
            StudyTask(courseID: course.id, title: "Pages", kind: .progress, planned: "2026-09-08", due: "2026-09-12"),
            StudyTask(courseID: course.id, title: "Essay", planned: "2026-09-09", due: "2026-09-10")
        ]
        XCTAssertEqual(CourseWork.relevantDay(for: state.tasks[0], from: "2026-09-08"), "2026-09-12")
        XCTAssertEqual(state.tasks[0].calendarDay, "2026-09-12")
        XCTAssertEqual(state.tasks[1].calendarDay, "2026-09-10")
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-11", in: state, progress: true).count, 1)
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-11", in: state, progress: true, exactDay: true).count, 0)
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-12", in: state, progress: true, exactDay: true).count, 1)
        XCTAssertEqual(CourseWork.tasks(courseID: course.id, from: "2026-09-13", in: state, progress: true).count, 0)
    }
    func testNotesDraftMergesWithLiveProgress() {
        let original = StudyTask(title: "Notes", kind: .progress, current: 3)
        var draft = original; draft.notes = "Keep this edit"
        var live = original; live.current = 10
        let merged = StudyTask.merging(draft: draft, baseline: original, latest: live)
        XCTAssertEqual(merged.notes, "Keep this edit")
        XCTAssertEqual(merged.current, 10)
    }
    @MainActor func testDirectProgressClampsAndDoesNotDuplicateEntries() async throws {
        let store = try Store(database: db())
        let task = StudyTask(title: "Notes", kind: .progress, start: 17, target: 49, current: 25)
        store.save(task)
        store.updateProgress(task.id, to: 26)
        store.updateProgress(task.id, to: 26)
        XCTAssertEqual(store.state.activities.count, 1)
        store.updateProgress(task.id, to: 999)
        XCTAssertEqual(store.state.tasks[0].current, 50)
        XCTAssertTrue(store.state.tasks[0].isProgressComplete)
        XCTAssertFalse(store.state.tasks[0].completed)
        store.updateProgress(task.id, to: 0)
        XCTAssertEqual(store.state.tasks[0].current, 17)
        XCTAssertFalse(store.state.tasks[0].completed)
    }
    @MainActor func testStoreRaisesProgressBelowRangeStart() async throws {
        let database = try db()
        var snapshot = Snapshot()
        snapshot.setupComplete = true
        var task = StudyTask(title: "Notes", kind: .progress, start: 17, target: 49, current: 25)
        task.current = 16
        snapshot.tasks = [task]
        try database.save(snapshot)
        let store = try Store(database: database)
        XCTAssertEqual(store.state.tasks[0].current, 17)
    }
    @MainActor func testPracticeTasksAndRulesNormalizeToCheckbox() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpusPractice-" + UUID().uuidString).appendingPathComponent("test.sqlite")
        let database = try Database(url: url)
        var snapshot = Snapshot()
        snapshot.setupComplete = true
        snapshot.tasks = [StudyTask(title: "Drill", kind: .practice)]
        var rule = QuizRule(title: "Practice set", itemKind: .task, startDate: Day.today)
        rule.taskKind = .practice
        snapshot.rules = [rule]
        try database.save(snapshot)
        let store = try Store(database: Database(url: url))
        XCTAssertEqual(store.state.tasks.first?.kind, .checkbox)
        XCTAssertEqual(store.state.rules.first?.taskKind, .checkbox)
        XCTAssertEqual(try Database(url: url).load().tasks.first?.kind, .checkbox)
    }
    @MainActor func testLegacyRhythmTasksMigratePlannedToDue() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpusRhythmMigrate-" + UUID().uuidString).appendingPathComponent("test.sqlite")
        let database = try Database(url: url)
        var snapshot = Snapshot()
        snapshot.setupComplete = true
        let rule = QuizRule(title: "Review", weekdays: Array(1...7), itemKind: .task, startDate: "2026-09-08", endDate: "2026-10-20")
        let id = "occurrence-1"
        snapshot.rules = [rule]
        snapshot.tasks = [
            StudyTask(id: id, title: "Review", planned: "2026-09-08", ruleID: rule.id, occurrence: "2026-09-08"),
            StudyTask(title: "Edited", planned: "2026-09-09", due: "2026-09-12", ruleID: rule.id, occurrence: "2026-09-09")
        ]
        try database.save(snapshot)
        let store = try Store(database: Database(url: url))
        let migrated = try XCTUnwrap(store.state.tasks.first { $0.id == id })
        XCTAssertEqual(migrated.due, "2026-09-08")
        XCTAssertNil(migrated.planned)
        XCTAssertEqual(migrated.occurrence, "2026-09-08")
        let edited = try XCTUnwrap(store.state.tasks.first { $0.title == "Edited" })
        XCTAssertEqual(edited.due, "2026-09-12")
        XCTAssertEqual(edited.planned, "2026-09-09")
        XCTAssertEqual(edited.id, store.state.tasks.first { $0.title == "Edited" }?.id)
    }
    func testRhythmCaptionShowsDueDayWithoutRepeatPattern() {
        let rule = QuizRule(title: "Review", weekdays: [3], itemKind: .task, startDate: "2026-09-01", endDate: "2026-10-20")
        let task = StudyTask(title: "Review", due: "2026-09-14", ruleID: rule.id, occurrence: "2026-09-14")
        XCTAssertEqual(task.rhythmCaption(), "Due \(Day.label("2026-09-14"))")
        XCTAssertEqual(StudyTask(title: "Review", planned: "2026-09-15", ruleID: rule.id).rhythmCaption(), Day.label("2026-09-15"))
        XCTAssertNil(StudyTask(title: "One-off", due: "2026-09-14").rhythmCaption())
    }
    func testArchiveKeepsDistinctRhythmOccurrences() {
        let rule = "weekly"
        let items = [
            StudyTask(title: "Review", due: "2026-09-10", completed: true, ruleID: rule, occurrence: "2026-09-10"),
            StudyTask(title: "Review", due: "2026-09-17", completed: true, ruleID: rule, occurrence: "2026-09-17"),
            StudyTask(title: "One-off", due: "2026-09-12", completed: true)
        ]
        var seen = Set<String>()
        let collapsed = items.filter { task in
            guard let ruleID = task.ruleID else { return true }
            return seen.insert(ruleID).inserted
        }
        XCTAssertEqual(collapsed.count, 2)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
        XCTAssertEqual(items.map(\.due), ["2026-09-10", "2026-09-17", "2026-09-12"])
    }
    @MainActor func testEditingRhythmPreservesModifiedOccurrenceDates() async throws {
        let store = try Store(database: db())
        var rule = QuizRule(title: "Drill", weekdays: Array(1...7), itemKind: .task, startDate: Day.today, endDate: Day.adding(10))
        store.saveRule(rule)
        var edited = try XCTUnwrap(store.state.tasks.first)
        let originalID = edited.id
        edited.due = Day.adding(3)
        edited.notes = "Changed"
        store.save(edited)
        rule.title = "Drill updated"
        store.saveRule(rule)
        XCTAssertTrue(store.state.tasks.contains { $0.id == originalID && $0.due == Day.adding(3) && $0.notes == "Changed" })
    }
    @MainActor func testProgressUpdatePreservesHistoryAndExplicitSaveSemantics() async throws {
        let store = try Store(database: db())
        let task = StudyTask(title: "Chapter", kind: .progress, due: "2026-09-20", start: 1, target: 40, current: 10)
        store.save(task)
        store.updateProgress(task.id, to: 15)
        XCTAssertEqual(store.state.activities.count, 1)
        var edited = store.state.tasks[0]
        edited.title = "Chapter 2"
        edited.current = 15
        store.save(edited)
        store.updateProgress(edited.id, to: 18)
        XCTAssertEqual(store.state.tasks[0].title, "Chapter 2")
        XCTAssertEqual(store.state.tasks[0].current, 18)
        XCTAssertEqual(store.state.activities.count, 2)
        store.undo()
        XCTAssertEqual(store.state.tasks[0].current, 15)
    }
    @MainActor func testEndToEndWorkflowSeed() async throws {
        let store = try Store(database: db())
        store.setup()
        XCTAssertTrue(store.state.courses.isEmpty)
        XCTAssertTrue(store.state.rules.isEmpty)
        let lit = Course(name: "Example list")
        store.save(lit)
        store.save(StudyTask(courseID: lit.id, title: "Read ch. 3", due: Day.adding(1)))
        store.save(StudyTask(courseID: lit.id, title: "Pages", kind: .progress, due: Day.today, start: 10, target: 40, current: 12))
        store.save(Assessment(courseID: lit.id, title: "Essay check", day: Day.adding(3), confirmed: true, topics: "Prompt A"))
        store.save(ScheduleBlock(courseID: lit.id, title: "Office hours", day: Day.today, startMinute: 16 * 60, duration: 30))
        XCTAssertEqual(store.state.tasks.filter { $0.courseID == lit.id }.count, 2)
        XCTAssertEqual(CourseWork.tasks(courseID: lit.id, from: Day.today, in: store.state, progress: true, exactDay: true).count, 1)
        XCTAssertEqual(CourseWork.assessments(courseID: lit.id, from: Day.today, in: store.state).count, 1)
        var task = store.state.tasks.first { $0.title == "Read ch. 3" }!
        task.completed = true
        store.save(task)
        store.deleteArchivedTasks()
        XCTAssertNil(store.state.tasks.first { $0.title == "Read ch. 3" })
        store.undo()
        XCTAssertNotNil(store.state.tasks.first { $0.title == "Read ch. 3" })
    }
    func testJournalMathFindsInlineAndDisplayLaTeX() {
        let spans = JournalMath.spans(in: "Energy $E=mc^2$ and\n$$\\frac{a}{b}$$\ncode `$not$`")
        XCTAssertEqual(spans.map(\.latex), ["E=mc^2", "\\frac{a}{b}"])
        XCTAssertEqual(spans.map(\.display), [false, true])
        XCTAssertEqual(spans[0].openRange.length, 1)
        XCTAssertEqual(spans[1].openRange.length, 2)
        XCTAssertTrue(JournalMath.spans(in: "almost $open").isEmpty)
        XCTAssertTrue(JournalMath.spans(in: "`$x$`").isEmpty)
        let code = JournalCode.spans(in: "use `let x` and ```not a block```")
        XCTAssertEqual(code.map { ($0.innerRange.location, $0.innerRange.length) }.count, 2)
        XCTAssertEqual(( "use `let x` and ```not a block```" as NSString).substring(with: code[0].innerRange), "let x")
        let source = "intro\n```swift\nlet value = 1\n```\n$x$"
        let blocks = JournalCode.blocks(in: source)
        XCTAssertEqual(blocks.map(\.language), ["swift"])
        XCTAssertEqual((source as NSString).substring(with: blocks[0].innerRange), "let value = 1\n")
        XCTAssertTrue(JournalMath.spans(in: source).map(\.latex) == ["x"])
        let tokens = CodeHighlight.tokens(in: "let value = 1 // hi", language: "swift")
        XCTAssertTrue(tokens.contains { $0.1 == .keyword })
        XCTAssertTrue(tokens.contains { $0.1 == .comment })
        XCTAssertEqual(ListNote(markdown: "# Hello").displayTitle, "Untitled note")
        XCTAssertEqual(ListNote(title: "Calc", markdown: "body").displayTitle, "Calc")
    }
    @MainActor func testListNotesPersistAndStayOffToday() async throws {
        let store = try Store(database: db())
        let course = Course(name: "Calc", notesMarkdown: "See $x^2$")
        store.save(course)
        store.save(StudyTask(courseID: course.id, title: "Homework", due: Day.today))
        XCTAssertEqual(store.course(course.id)?.listNotes.map(\.markdown), ["See $x^2$"])
        let first = store.course(course.id)!.listNotes[0]
        store.saveListNote(course.id, ListNote(id: first.id, title: "Lecture", markdown: "Updated $$1+1$$"))
        XCTAssertEqual(store.course(course.id)?.listNotes.map(\.markdown), ["Updated $$1+1$$"])
        XCTAssertNotNil(store.addListNote(course.id))
        XCTAssertEqual(store.course(course.id)?.listNotes.count, 2)
        var renamed = store.course(course.id)!
        renamed.name = "Calculus"
        store.save(renamed)
        XCTAssertEqual(store.course(course.id)?.listNotes.map(\.markdown), ["Updated $$1+1$$", ""])
        XCTAssertTrue(store.state.tasks.contains { $0.title == "Homework" && $0.isInToday(on: Day.today) })
        XCTAssertFalse(store.state.tasks.contains { $0.title.contains("$") })
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Course(name: "Old"))) as! [String: Any]
        payload.removeValue(forKey: "notesMarkdown")
        payload.removeValue(forKey: "notes")
        let decoded = try JSONDecoder().decode(Course.self, from: try JSONSerialization.data(withJSONObject: payload))
        XCTAssertTrue(decoded.listNotes.isEmpty)
    }
    func testUpdateCompletionRequiresInstalledVersion() {
        XCTAssertTrue(AppUpdateCompletion.didInstall("0.5.6", current: "0.5.6"))
        XCTAssertTrue(AppUpdateCompletion.didInstall("0.5.6", current: "0.5.7"))
        XCTAssertFalse(AppUpdateCompletion.didInstall("0.5.6", current: "0.5.5"))
    }
}
