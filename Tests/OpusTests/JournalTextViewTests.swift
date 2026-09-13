import AppKit
import XCTest
import OpusCore
@testable import Opus

final class JournalTextViewTests: XCTestCase {
    @MainActor private func editor(_ source: String) -> JournalTextView {
        _ = NSApplication.shared
        let editor = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        editor.isRichText = true
        editor.allowsUndo = true
        editor.textStorage?.setAttributedString(JournalRichText.attributed(source))
        return editor
    }
    @MainActor func testNativeAttachmentSerializationPreservesDuplicateEmbedsAndNewlines() async {
        let token = JournalLink.task("same").embedToken
        let source = "🪴\n\n" + token + "\nBetween\n" + token + "\n"
        let rich = JournalRichText.attributed(source)
        XCTAssertEqual(JournalRichText.markdown(rich), source)
        XCTAssertEqual(rich.string.filter { $0 == "\u{fffc}" }.count, 2)
    }
    @MainActor func testAdjacentCopiesSharingOneAttachmentRemainDistinct() async {
        let token = JournalLink.task("copied").embedToken
        let attachment = JournalRichText.attributed(token)
        let copied = NSMutableAttributedString(attributedString: attachment)
        copied.append(attachment)
        XCTAssertEqual(JournalRichText.markdown(copied), token + token)
    }
    @MainActor func testTypingAndArrowMovementAcrossAnEmbedUseOneTextFlow() async {
        let token = JournalLink.task("task").embedToken
        let view = editor("Before\n" + token + "\nAfter")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        view.moveRight(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 8, length: 0))
        view.moveLeft(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 7, length: 0))
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 7, length: 1))
        view.setSelectedRange(NSRange(location: 9, length: 0))
        for character in "Typed " { view.insertText(String(character), replacementRange: view.selectedRange()) }
        XCTAssertEqual(JournalRichText.markdown(view.attributedString()), "Before\n" + token + "\nTyped After")
    }
    @MainActor func testInsertionUsesUTF16CaretAndLeavesCursorAfterEmbed() async {
        let view = editor("🪴 middle end")
        view.setSelectedRange(NSRange(location: 9, length: 0))
        view.insertEmbed(.task("new"), replacing: view.selectedRange())
        view.insertText("continued", replacementRange: view.selectedRange())
        XCTAssertEqual(JournalRichText.markdown(view.attributedString()), "🪴 middle\n![[task:new]]\ncontinued end")
    }
    @MainActor func testCopyProducesPortableMarkdownAndNativeUndoRestoresDeletedEmbed() async {
        let token = JournalLink.task("task").embedToken
        let view = editor("Before\n" + token + "\nAfter")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 7, length: 1))
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string], owner: nil)
        XCTAssertTrue(view.writeSelection(to: pasteboard, type: .string))
        XCTAssertEqual(pasteboard.string(forType: .string), token)
        view.breakUndoCoalescing()
        view.insertText("", replacementRange: view.selectedRange())
        XCTAssertEqual(JournalRichText.markdown(view.attributedString()), "Before\n\nAfter")
        view.undoManager?.undo()
        XCTAssertEqual(JournalRichText.markdown(view.attributedString()), "Before\n" + token + "\nAfter")
        pasteboard.releaseGlobally()
    }
    @MainActor func testProgressEmbedShowsCompletedAmountAndRemainingWork() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("journal.sqlite")))
        let task = StudyTask(title: "Reading", kind: .progress, start: 17, target: 49, current: 25)
        store.save(task)

        let presentation = JournalEmbedPresentation(link: .task(task.id), store: store, day: Day.today)

        XCTAssertTrue(presentation.detail.contains("9 of 33 pages"))
        XCTAssertTrue(presentation.detail.contains("24 left"))
    }
}
