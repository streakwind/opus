import XCTest
@testable import OpusGTKSupport
@testable import OpusCore

final class PresentationTests: XCTestCase {
    func testNavigationAndWorkSections() {
        let course = Course(name: "Bio", color: "green")
        var state = Snapshot(courses: [course], setupComplete: true)
        state.tasks = [
            StudyTask(courseID: course.id, title: "Essay", due: Day.today),
            StudyTask(courseID: course.id, title: "Pages", kind: .progress, due: Day.today, start: 1, target: 20, current: 4),
            StudyTask(courseID: course.id, title: "Old", due: Day.adding(-3), completed: true),
            StudyTask(title: "Inbox", due: Day.today),
            StudyTask(courseID: course.id, title: "Review", due: Day.today, ruleID: "r1", occurrence: Day.today),
            StudyTask(courseID: course.id, title: "Review", due: Day.adding(7), ruleID: "r1", occurrence: Day.adding(7))
        ]
        state.assessments = [
            Assessment(courseID: course.id, title: "Quiz", day: Day.adding(1), topics: "Ch 2")
        ]
        let nav = LinuxPresentation.navItems(selection: .section(.today), courses: state.courses)
        XCTAssertTrue(nav.contains { $0.id == "calendar" })
        XCTAssertTrue(nav.contains { $0.id == "list:" + course.id })
        let rows = LinuxPresentation.workRows(in: state, selection: .section(.today), query: "")
        XCTAssertEqual(rows.assessments.count, 1)
        XCTAssertEqual(rows.progress.count, 1)
        XCTAssertEqual(rows.tasks.filter { $0.title == "Review" }.count, 1)
        XCTAssertTrue(rows.tasks.contains { $0.title == "Inbox" })
        let archive = LinuxPresentation.workRows(in: state, selection: .section(.archive), query: "")
        XCTAssertEqual(archive.tasks.map(\.title), ["Old"])
        let search = LinuxPresentation.workRows(in: state, selection: .section(.all), query: "quiz")
        XCTAssertEqual(search.assessments.map(\.title), ["Quiz"])
        XCTAssertTrue(LinuxPresentation.matchesQuery("bio", title: "Essay", courseName: "Bio"))
    }

    func testCalendarScheduleAndRhythmProjection() {
        let course = Course(name: "Calc", color: "blue", classTimes: [ClassTime(startMinute: 480, endMinute: 530, days: [Calendar.current.component(.weekday, from: Date())])])
        var state = Snapshot(courses: [course], setupComplete: true)
        let today = Day.today
        state.tasks = [StudyTask(courseID: course.id, title: "Homework", due: today)]
        state.assessments = [Assessment(courseID: course.id, title: "Exam", day: today, confirmed: true)]
        state.schedule = [ScheduleBlock(courseID: course.id, title: "Office", day: today, startMinute: 600, duration: 30)]
        state.rules = [QuizRule(courseID: course.id, title: "Drill", weekdays: [2,4], itemKind: .task, startDate: today)]
        let days = LinuxPresentation.calendarDays(in: state, period: .week, anchor: today, selected: today, query: "")
        XCTAssertFalse(days.isEmpty)
        XCTAssertTrue(days.contains { $0.day == today && $0.items.count >= 2 })
        let blocks = LinuxPresentation.scheduleBlocks(in: state, days: [today], query: "")
        XCTAssertTrue(blocks.contains { $0.title == "Office" })
        XCTAssertTrue(blocks.contains { $0.isClass })
        let rhythms = LinuxPresentation.rhythmRows(in: state, query: "Drill")
        XCTAssertEqual(rhythms.count, 1)
        XCTAssertEqual(CourseColor.rgba(for: "#112233").hex, "#112233")
        XCTAssertEqual(CourseColor.names.count, 12)
        let undated = StudyTask(courseID: course.id, title: "Someday")
        state.tasks.append(undated)
        state.tasks.append(StudyTask(courseID: course.id, title: "Due work", due: today))
        let calendar = LinuxPresentation.calendarDays(in: state, period: .week, anchor: today, selected: today, query: "")
        XCTAssertTrue(calendar.contains { day in day.day == today && day.items.contains { $0.title == "Due work" } })
        XCTAssertFalse(calendar.contains { day in day.items.contains { $0.title == "Someday" } })
        let undatedRows = LinuxPresentation.undatedTasks(in: state, query: "")
        XCTAssertEqual(undatedRows.map(\.title), ["Someday"])
    }
}

final class SessionTests: XCTestCase {
    @MainActor private func session() throws -> LinuxSession {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpusGTK-" + UUID().uuidString).appendingPathComponent("test.sqlite")
        return try LinuxSession(store: Store(database: Database(url: url)))
    }

    @MainActor func testTaskAssessmentCourseRuleAndArchiveFlow() async throws {
        let app = try session()
        _ = app.handle(.setupComplete)
        _ = app.handle(.newList("Biology"))
        XCTAssertNotNil(app.selection.courseID)
        var draft = WorkDraftModel.blank(courseID: app.selection.courseID, day: Day.today, kind: .task)
        draft.title = "Read"
        XCTAssertTrue(app.handle(.saveWork(draft)).contains(.closeEditor))
        XCTAssertEqual(app.store.state.tasks.count, 1)
        let taskID = app.store.state.tasks[0].id
        _ = app.handle(.toggleTask(taskID))
        XCTAssertTrue(app.store.state.tasks[0].completed)
        app.selection = .section(.archive)
        XCTAssertEqual(app.workRows().tasks.count, 1)
        _ = app.handle(.confirmArchiveDeleteAll)
        XCTAssertTrue(app.store.state.tasks.isEmpty)
        var assessment = WorkDraftModel.blank(courseID: nil, day: Day.adding(2), kind: .assessment)
        assessment.title = "Quiz"; assessment.notes = "Ch 1"
        _ = app.handle(.saveWork(assessment))
        XCTAssertEqual(app.store.state.assessments.count, 1)
        let assessmentID = app.store.state.assessments[0].id
        _ = app.handle(.prepareTask(assessmentID))
        XCTAssertTrue(app.store.state.tasks.contains { $0.title.hasPrefix("Prepare:") })
        var rule = RuleDraftModel(); rule.title = "Weekly"; rule.workKind = .assessment; rule.weekdays = [Calendar.current.component(.weekday, from: Date())]
        _ = app.handle(.saveRule(rule))
        XCTAssertFalse(app.store.state.rules.isEmpty)
        _ = app.handle(.undo)
        XCTAssertTrue(app.handle(.exportJSON).contains { if case .exportJSON = $0 { return true }; return false })
    }

    @MainActor func testScheduleCreateAndReschedule() async throws {
        let app = try session()
        _ = app.handle(.setupComplete)
        let commands = app.handle(.scheduleCreate(day: Day.today, startY: 480, endY: 540))
        guard case .openScheduleEditor(let draft) = commands.first else { return XCTFail("expected schedule editor") }
        var edited = draft; edited.title = "Lab"
        _ = app.handle(.saveSchedule(edited))
        XCTAssertEqual(app.store.state.schedule.count, 1)
        let id = app.store.state.schedule[0].id
        _ = app.handle(.calendarDrop(payload: "schedule:" + id, day: Day.adding(1)))
        XCTAssertEqual(app.store.state.schedule[0].day, Day.adding(1))
    }

    func testDraftValidation() {
        var work = WorkDraftModel(); work.title = ""; XCTAssertNotNil(work.validationError)
        work.title = "Ok"; work.kind = .progress; work.start = 10; work.target = 5; work.current = 9
        XCTAssertNotNil(work.validationError)
        var rule = RuleDraftModel(); rule.title = "X"; rule.weekdays = []
        XCTAssertNotNil(rule.validationError)
        var course = CourseDraftModel(name: "Calc", classTimes: [
            ClassTime(id: "a:b", startMinute: 540, endMinute: 600, days: [2, 3, 4])
        ])
        XCTAssertNil(course.validationError)
        course.classTimes = [ClassTime(startMinute: 600, endMinute: 500, days: [2])]
        XCTAssertEqual(course.validationError, "Check class times.")
        course.classTimes = [ClassTime(startMinute: 540, endMinute: 600, days: [])]
        XCTAssertEqual(course.validationError, "Check class times.")
    }

    func testClassTimeCodecRoundTrip() {
        let times = [
            ClassTime(id: "legacy", startMinute: 480, endMinute: 530, days: [2, 3, 4, 5, 6]),
            ClassTime(id: "lab:section", startMinute: 780, endMinute: 900, days: [4])
        ]
        let encoded = ClassTimeCodec.encode(times)
        XCTAssertEqual(encoded, "legacy|480|530|2,3,4,5,6;lab:section|780|900|4")
        let parsed = ClassTimeCodec.parse(encoded)
        XCTAssertEqual(parsed, times)
        XCTAssertTrue(ClassTimeCodec.parse("").isEmpty)
        XCTAssertTrue(ClassTimeCodec.parse("broken").isEmpty)
        let emptyDays = ClassTimeCodec.parse("x|540|600|")
        XCTAssertEqual(emptyDays.count, 1)
        XCTAssertTrue(emptyDays[0].days.isEmpty)
    }

    @MainActor func testSaveCourseWithClassTimes() async throws {
        let app = try session()
        _ = app.handle(.setupComplete)
        var draft = CourseDraftModel(
            name: "Physics",
            color: "teal",
            classTimes: [
                ClassTime(id: "morning", startMinute: 540, endMinute: 600, days: [2, 4, 6]),
                ClassTime(id: "id:with:colons", startMinute: 780, endMinute: 850, days: [3])
            ]
        )
        let commands = app.handle(.saveCourse(draft))
        XCTAssertTrue(commands.contains(.closeEditor))
        XCTAssertEqual(app.store.state.courses.count, 1)
        let course = app.store.state.courses[0]
        XCTAssertEqual(course.name, "Physics")
        XCTAssertEqual(course.resolvedClassTimes.count, 2)
        XCTAssertEqual(course.resolvedClassTimes[0].days, [2, 4, 6])
        XCTAssertEqual(course.resolvedClassTimes[1].id, "id:with:colons")
        draft = .from(course)
        draft.classTimes[0].endMinute = 530
        XCTAssertTrue(app.handle(.saveCourse(draft)).contains { if case .showError = $0 { return true }; return false })
    }

    @MainActor func testCalendarNavigationSettingsAndSearch() async throws {
        let app = try session()
        _ = app.handle(.setupComplete)
        _ = app.handle(.select("calendar"))
        XCTAssertEqual(app.selection, .section(.calendar))
        _ = app.handle(.calendarPeriod(.week))
        XCTAssertEqual(app.calendarPeriod, .week)
        _ = app.handle(.calendarNavigate(1))
        _ = app.handle(.select("schedule"))
        _ = app.handle(.schedulePeriod(.day))
        XCTAssertEqual(app.schedulePeriod, .day)
        _ = app.handle(.setAppearance(.dark))
        XCTAssertEqual(app.appearance, .dark)
        _ = app.handle(.search("lab"))
        XCTAssertEqual(app.query, "lab")
        XCTAssertTrue(app.handle(.openSettings).contains(.openSettings))
        XCTAssertTrue(app.handle(.help).contains(.openHelp))
    }
}
