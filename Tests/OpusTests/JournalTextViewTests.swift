import AppKit
import XCTest
import SwiftUI
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

        XCTAssertTrue(presentation.detail.contains("9 of 33"))
        XCTAssertTrue(presentation.detail.contains("24 left"))
    }
    @MainActor func testMathRendererDrawsInlineAndDisplayLaTeX() async {
        MathRenderer.prepareFonts()
        XCTAssertNotNil(MathRenderer.image(latex: "E=mc^2", display: false, color: .labelColor, fontSize: 17))
        XCTAssertNotNil(MathRenderer.image(latex: #"\frac{a}{b}"#, display: true, color: .labelColor, fontSize: 20))
    }
    @MainActor func testPreviewRendersOnceAndNeverChangesSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("journal.sqlite")))
        let source = "# Heading\n**Bold** and $x^2$\n```swift\nlet n = 42\n```\n"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, preview: true)
        let coordinator = parent.makeCoordinator()
        let view = editor("")
        coordinator.load(source, in: view)
        XCTAssertEqual(view.string, "Heading\nBold and \u{fffc}\nlet n = 42\n")
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(JournalRichText.markdown(view.attributedString()).contains("$x^2$"))
        XCTAssertEqual(coordinator.source, source)
        let range = (view.string as NSString).range(of: "let")
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, .systemPurple)
        XCTAssertEqual(view.textStorage?.attribute(JournalRichText.codeBlock, at: range.location, effectiveRange: nil) as? String, "swift")
        coordinator.parent.preview = false
        coordinator.load(source, in: view)
        XCTAssertEqual(JournalRichText.markdown(view.attributedString()), source)
        XCTAssertTrue(view.isEditable)
    }
    @MainActor func testEmbedExamplesInsideCodeStayLiteral() async {
        let source = "```\n![[task:example]]\n```\n`![[task:inline]]`"
        XCTAssertEqual(JournalRichText.attributed(source).string, source)
    }

    @MainActor func testReturnContinuesListsAndCodeIndentation() async {
        for (source, expected) in [
            ("- [x] Done", "- [x] Done\n- [ ] "),
            ("- [] hello", "- [] hello\n- [ ] "),
            ("☐ hello", "☐ hello\n- [ ] "),
            ("2. Item", "2. Item\n3. "),
            ("- ", ""),
            ("☐ ", ""),
            ("```swift\n    let n = 1", "```swift\n    let n = 1\n    ")
        ] {
            let view = editor(source)
            view.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
            view.insertNewline(nil)
            XCTAssertEqual(view.string, expected, source)
        }
    }
    @MainActor func testFormattingWritesPortableMarkdown() async {
        let view = editor("word")
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.toggleBoldface(nil)
        XCTAssertEqual(view.string, "**word**")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 4))
    }

    @MainActor func testProsePreviewHandlesNestedFormattingLinksAndEscapes() async {
        let source = #"**bold _italic_** [link](https://example.com) ![image](example.com) \*literal\* `code`"#
        let rendered = MarkdownProse.render(NSAttributedString(string: source))
        XCTAssertEqual(rendered.string, "bold italic link image *literal* code")
        let link = (rendered.string as NSString).range(of: "link")
        XCTAssertEqual(rendered.attribute(.link, at: link.location, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
        let image = (rendered.string as NSString).range(of: "image")
        XCTAssertEqual(rendered.attribute(.link, at: image.location, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
        XCTAssertEqual(MarkdownProse.render(NSAttributedString(string: "- [ ] open\n- [] also\n- [x] done\n- item")).string, "☐ open\n☐ also\n☑ done\n• item")
        let loose = MarkdownProse.render(NSAttributedString(string: "see [hyperlink](to nothing)"))
        XCTAssertEqual(loose.string, "see hyperlink")
        XCTAssertNotNil(loose.attribute(.link, at: (loose.string as NSString).range(of: "hyperlink").location, effectiveRange: nil))
        let italic = (rendered.string as NSString).range(of: "italic")
        let font = rendered.attribute(.font, at: italic.location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

}
