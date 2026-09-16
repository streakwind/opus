import XCTest
@testable import OpusCore

final class SearchIndexTests: XCTestCase {
    func testSearchIncludesHiddenCompletedAndPastWork() {
        var state = Snapshot()
        let course = Course(name: "Biology", listOnly: true)
        state.courses = [course]
        state.tasks = [StudyTask(courseID: course.id, title: "Finished reading", completed: true), StudyTask(title: "Reading progress", kind: .progress)]
        state.assessments = [Assessment(title: "Old exam", day: "2020-01-01")]
        let index = SearchIndex(state: state)
        XCTAssertEqual(index.search("biology", category: .lists).first?.targetID, course.id)
        XCTAssertEqual(index.search("finished biology").first?.category, .tasks)
        XCTAssertEqual(index.search("progress", category: .progress).count, 1)
        XCTAssertEqual(index.search("old exam").first?.category, .assessments)
    }

    func testNoteNamesOnlyAndNoJournalEntries() {
        var state = Snapshot()
        state.courses = [Course(name: "Study", notes: [ListNote(title: "Revision plan", markdown: "secretbody"), ListNote(markdown: "hiddenheading")])]
        state.journal = [JournalEntry(title: "privatejournal", markdown: "journalbody")]
        let index = SearchIndex(state: state)
        XCTAssertEqual(index.search("revision").first?.category, .notes)
        for query in ["secretbody", "hiddenheading", "privatejournal", "journalbody"] {
            XCTAssertTrue(index.search(query).isEmpty, query)
        }
        XCTAssertEqual(index.search("Journal").map(\.category), [.pages])
    }

    func testRankingNormalizationAndCategoryFilters() {
        var state = Snapshot()
        state.courses = [Course(name: "Café")]
        state.tasks = [StudyTask(title: "Visit café"), StudyTask(title: "Café"), StudyTask(title: "Other", notes: "café")]
        let results = SearchIndex(state: state).search("  CAFE  ", category: .tasks)
        XCTAssertEqual(results.map(\.title), ["Café", "Visit café", "Other"])
        XCTAssertTrue(SearchIndex(state: state).search("missing").isEmpty)
    }

    func testOnlyNextUnfinishedRhythmOccurrenceIsIndexed() {
        var state = Snapshot()
        state.tasks = [
            StudyTask(id: "later", title: "Read", due: "2026-10-02", ruleID: "r"),
            StudyTask(id: "done", title: "Read", due: "2026-09-01", completed: true, ruleID: "r"),
            StudyTask(id: "next", title: "Read", due: "2026-09-14", ruleID: "r")
        ]
        state.assessments = [
            Assessment(id: "past", title: "Quiz", day: "2026-09-14", ruleID: "q"),
            Assessment(id: "future", title: "Quiz", day: "2026-09-20", ruleID: "q"),
            Assessment(id: "today", title: "Quiz", day: "2026-09-15", ruleID: "q")
        ]
        let index = SearchIndex(state: state, today: "2026-09-15")
        XCTAssertEqual(index.search("Read").map(\.targetID), ["next"])
        XCTAssertEqual(index.search("Quiz").map(\.targetID), ["today"])
        XCTAssertTrue(index.search("2026-10-02").isEmpty)
    }

    func testScheduleExcludedAndExplicitSorts() {
        var state = Snapshot()
        state.courses = [Course(id: "a", name: "Alpha"), Course(id: "z", name: "Zulu")]
        state.schedule = [ScheduleBlock(title: "Scheduled secret")]
        state.tasks = [
            StudyTask(id: "b", courseID: "a", title: "Beta", due: "2026-09-20"),
            StudyTask(id: "a", courseID: "z", title: "Alpha", due: "2026-09-21"),
            StudyTask(id: "c", title: "Charlie")
        ]
        let index = SearchIndex(state: state)
        XCTAssertTrue(index.search("schedule").isEmpty)
        XCTAssertEqual(index.search("", category: .tasks, sort: .name).map(\.targetID), ["a", "b", "c"])
        XCTAssertEqual(index.search("", category: .tasks, sort: .dueDate).map(\.targetID), ["b", "a", "c"])
        XCTAssertEqual(index.search("", category: .tasks, sort: .list).map(\.targetID), ["b", "c", "a"])
    }

    func testGroupScopeSeparatesCalendarWork() {
        var first = Course(id: "one", name: "One")
        first.group = "First"
        var second = Course(id: "two", name: "Two")
        second.group = "Second"
        let state = Snapshot(courses: [first, second, Course(id: "none", name: "Ungrouped")])
        XCTAssertTrue(state.matchesGroup("one", group: "First"))
        XCTAssertEqual(state.matchesGroup("two", group: "First"), false)
        XCTAssertEqual(state.matchesGroup(nil, group: "First"), false)
        XCTAssertEqual(state.matchesGroup("none", group: "First"), false)
        XCTAssertTrue(state.matchesGroup(nil, group: ""))
        XCTAssertTrue(state.matchesGroup("two", group: ""))
        XCTAssertEqual(state.courses(inGroup: "First").map(\.id), ["one"])
        XCTAssertEqual(state.defaultCourseID(inGroup: "First"), "one")
        XCTAssertNil(state.defaultCourseID(inGroup: ""))
        XCTAssertEqual(state.courses(inGroup: "First", including: "two").map(\.id).sorted(), ["one", "two"])
    }

    func testListGroupsRoundTripAndLegacyDecoding() throws {
        var course = Course(name: "Biology")
        course.group = "School"
        let decoded = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertEqual(decoded.group, "School")
        course.group = nil
        let legacy = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertNil(legacy.group)
    }

    func testLegacyNoteIDsAreUniqueAcrossLists() {
        var state = Snapshot()
        state.courses = [Course(name: "One", notesMarkdown: "first"), Course(name: "Two", notesMarkdown: "second")]
        let notes = SearchIndex(state: state).search("", category: .notes)
        XCTAssertEqual(Set(notes.map(\.id)).count, 2)
    }
}
