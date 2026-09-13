import XCTest
@testable import OpusCore

final class JournalEditingTests: XCTestCase {
    func testMarkdownRoundTripsWhitespaceMultipleEmbedsAndUnicodeExactly() {
        let a = JournalLink.task("first").embedToken
        let b = JournalLink.assessment("second").embedToken
        let samples = ["", "\n\n", a, "\n" + a + "\n", "Before\n\n" + a + "\n\nBetween\n" + b + "\nAfter\n\n", a + b, "🪴 é" + a + "文", "![[schedule:session]]\n", "![[unknown:keep-me]]"]
        for sample in samples {
            var actual = sample
            for _ in 0..<100 { actual = JournalMarkdown.markdown(from: JournalMarkdown.blocks(from: actual)) }
            XCTAssertEqual(actual, sample)
        }
    }
    func testTypingBetweenEmbedsNeverAddsParagraphs() {
        let a = JournalLink.task("first").embedToken
        let b = JournalLink.task("second").embedToken
        var text = a + "\n\n" + b + "\n"
        for letter in "Typing a sentence" {
            var blocks = JournalMarkdown.blocks(from: text)
            guard case .text(let middle) = blocks[2] else { return XCTFail("Missing middle text") }
            blocks[2] = .text(middle + String(letter))
            text = JournalMarkdown.markdown(from: blocks)
        }
        XCTAssertEqual(text, a + "\n\nTyping a sentence" + b + "\n")
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 3)
    }
    @MainActor func testRemovingCarriedEmbedStaysRemovedAfterReopeningWithoutChangingHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try Database(url: folder.appendingPathComponent("journal.sqlite"))
        let store = try Store(database: db)
        let task = StudyTask(title: "Draft", due: "2027-01-03")
        store.save(task)
        let link = JournalLink.task(task.id)
        store.save(JournalEntry(day: "2027-01-01", title: task.title, markdown: "Existing comment", link: link))
        store.ensureJournalDocument(on: "2027-01-01")
        store.ensureJournalDocument(on: "2027-01-02")
        let history = try XCTUnwrap(store.journalDocument(on: "2027-01-01"))
        var second = try XCTUnwrap(store.journalDocument(on: "2027-01-02"))
        second.markdown = "Just prose now."
        store.save(second)
        let reopened = try Store(database: db)
        reopened.ensureJournalDocument(on: "2027-01-02")
        XCTAssertEqual(reopened.journalDocument(on: "2027-01-02")?.markdown, second.markdown)
        let migratedHistory = try XCTUnwrap(reopened.journalDocument(on: "2027-01-01")?.markdown)
        XCTAssertTrue(migratedHistory.contains(history.markdown))
        XCTAssertTrue(migratedHistory.contains("Existing comment"))
        XCTAssertEqual(reopened.journalTaskEmbeds(on: "2027-01-02").first?.markdown, "")
        second.markdown = link.embedToken + "\nReinserted"
        reopened.save(second)
        XCTAssertNil(reopened.journalDocument(on: second.day)?.omittedEmbeds)
    }
}
