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

    func testLegacyNoteIDsAreUniqueAcrossLists() {
        var state = Snapshot()
        state.courses = [Course(name: "One", notesMarkdown: "first"), Course(name: "Two", notesMarkdown: "second")]
        let notes = SearchIndex(state: state).search("", category: .notes)
        XCTAssertEqual(Set(notes.map(\.id)).count, 2)
    }
}
