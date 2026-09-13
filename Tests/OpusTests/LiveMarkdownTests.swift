import AppKit
import SwiftUI
import XCTest
import OpusCore
@testable import Opus

final class LiveMarkdownTests: XCTestCase {
    @MainActor private func liveEditor(_ source: String) throws -> (JournalNativeEditor.Coordinator, JournalTextView) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        view.allowsUndo = true
        coordinator.load(source, in: view)
        return (coordinator, view)
    }
    @MainActor func testMovingBetweenParagraphsRendersAndRevealsWithoutChangingSource() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "# Heading\n\n**bold** and $x^2$\n\nLast line"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        view.allowsUndo = true
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        coordinator.load(source, in: view)
        XCTAssertTrue(view.string.hasPrefix("# Heading"))
        XCTAssertFalse(view.string.contains("**bold**"))
        let bold = (view.string as NSString).range(of: "bold")
        view.setSelectedRange(NSRange(location: bold.location + 2, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertTrue(view.string.hasPrefix("Heading"))
        XCTAssertTrue(view.string.contains("**bold** and \u{fffc}"))
        XCTAssertFalse(view.string.contains("$x^2$"))
        XCTAssertEqual(coordinator.source, source)
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "# Heading\n\n**boXld** and $x^2$\n\nLast line")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        view.undoManager?.undo()
        XCTAssertEqual(coordinator.source, source)
        view.selectAll(nil)
        view.insertText("Replacement 🪴", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "Replacement 🪴")
        view.undoManager?.undo()
        XCTAssertEqual(coordinator.source, source)
    }
    @MainActor func testTypingAfterDisplayMathAndEmbedsDoesNotChangeOtherBlocks() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "$$\n\\frac{a}{b}\n$$\nyes\n\n![[task:first]]\n\n![[task:second]]\n"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load(source, in: view)
        let yes = (view.string as NSString).range(of: "yes")
        view.setSelectedRange(NSRange(location: NSMaxRange(yes), length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertFalse(view.string.contains("$$"))
        view.insertText(" more", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, source.replacingOccurrences(of: "yes", with: "yes more"))
        XCTAssertFalse(view.string.contains("$$"))
        var links: [JournalLink] = []
        view.attributedString().enumerateAttributes(in: NSRange(location: 0, length: view.attributedString().length)) { attrs, _, _ in
            if let link = JournalRichText.link(in: attrs) { links.append(link) }
        }
        XCTAssertEqual(links, [.task("first"), .task("second")])
    }
    @MainActor func testEmptyMarkdownBlockStaysVisibleWhenCaretLeaves() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "# \n\nPlain"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load(source, in: view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertTrue(view.string.hasPrefix("# "))
        XCTAssertEqual(coordinator.source, source)
    }
    @MainActor func testTypingFencedCodeDoesNotInsertExtraBlankLines() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let parent = JournalNativeEditor(markdown: .constant(""), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load("", in: view)
        for character in "```cpp" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "```cpp\n\n```\n")
        XCTAssertTrue(view.string.contains("```cpp"))
        XCTAssertTrue(view.string.contains("```"))
        XCTAssertNotNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: 0, effectiveRange: nil))
        for character in "hello" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        XCTAssertEqual(coordinator.source, "```cpp\nhello\n```\n")
        XCTAssertTrue(view.string.contains("```cpp"))
        let hello = (view.string as NSString).range(of: "hello")
        XCTAssertNotNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: hello.location, effectiveRange: nil))
        view.insertNewline(nil)
        for character in "world" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        XCTAssertEqual(coordinator.source, "```cpp\nhello\nworld\n```\n")
        XCTAssertTrue(view.string.contains("```"))
        guard let close = JournalCode.blocks(in: coordinator.source).first?.closeRange else {
            return XCTFail("expected a closed fence")
        }
        view.setSelectedRange(NSRange(location: close.location, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "```cpp\nhello\nworld\n```\n")
        XCTAssertFalse(view.string.contains("```"))
        XCTAssertTrue(view.string.contains("hello"))
        view.insertText("Great", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "```cpp\nhello\nworld\n```\nGreat")
        XCTAssertFalse(view.string.contains("```"))
        let outside = (view.string as NSString).range(of: "Great")
        XCTAssertNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: outside.location, effectiveRange: nil))
    }
    @MainActor func testClickingRenderedCodeMapsCaretBackIntoCodeBody() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "before\n```cpp\nhello\n```\nafter"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load(source, in: view)
        let renderedHello = (view.string as NSString).range(of: "hello")
        view.setSelectedRange(NSRange(location: renderedHello.location + 2, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertTrue(view.string.contains("```cpp"))
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "before\n```cpp\nheXllo\n```\nafter")
    }
    @MainActor func testPreviewedCodeDoesNotAbsorbTheNextParagraph() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "```cpp\nhello\n```\noutside"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load(source, in: view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertEqual(view.string, "hello\noutside")
        let hello = (view.string as NSString).range(of: "hello")
        let outside = (view.string as NSString).range(of: "outside")
        XCTAssertEqual(view.textStorage?.attribute(JournalRichText.codeBlock, at: hello.location, effectiveRange: nil) as? String, "cpp")
        XCTAssertNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: outside.location, effectiveRange: nil))
    }
    @MainActor func testMultilineCodeKeepsOneAttributeRun() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let source = "```cpp\n#include <iostream>\nsecond line\n```\nafter"
        let parent = JournalNativeEditor(markdown: .constant(source), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load(source, in: view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        let first = (view.string as NSString).range(of: "#include")
        var run = NSRange()
        let language = view.textStorage?.attribute(
            JournalRichText.codeBlock,
            at: first.location,
            longestEffectiveRange: &run,
            in: NSRange(location: 0, length: view.string.utf16.count)
        ) as? String
        XCTAssertEqual(language, "cpp")
        XCTAssertTrue((view.string as NSString).substring(with: run).contains("second line"))
        XCTAssertFalse((view.string as NSString).substring(with: run).contains("after"))
    }
    @MainActor func testFinishedCheckboxPreviewsWhileCaretStaysInTheBody() async throws {
        let (coordinator, view) = try liveEditor("- [ ] hello")
        let hello = (view.string as NSString).range(of: "hello")
        view.setSelectedRange(NSRange(location: hello.location + 2, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertFalse(view.string.contains("- ["))
        XCTAssertTrue(view.string.contains("☐"))
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "- [ ] heXllo")
        XCTAssertTrue(view.string.contains("☐"))
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "- [ ] heXllo\n- [ ] ")
        XCTAssertTrue(view.string.contains("☐"))
        XCTAssertTrue(view.string.contains("- [ ]"))
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "- [ ] heXllo\n")
        XCTAssertTrue(view.string.contains("☐"))
        XCTAssertFalse(view.string.contains("- ["))
    }
    @MainActor func testNavigatingIntoCheckboxMarkerRevealsSourceLikeBold() async throws {
        let (coordinator, view) = try liveEditor("- [ ] hello")
        let hello = (view.string as NSString).range(of: "hello")
        view.setSelectedRange(NSRange(location: hello.location + 1, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertFalse(view.string.contains("- ["))
        XCTAssertTrue(view.string.contains("☐"))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertTrue(view.string.contains("- [ ]"))
        XCTAssertTrue(view.string.contains("hello"))
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "hello").location + 1, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertFalse(view.string.contains("- ["))
        XCTAssertTrue(view.string.contains("☐"))
    }
    @MainActor func testClickingRenderedCheckboxTogglesSource() async throws {
        let (coordinator, view) = try liveEditor("- [ ] hello")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        let box = (view.string as NSString).range(of: "☐")
        XCTAssertNotEqual(box.location, NSNotFound)
        view.onCheckbox?(box.location)
        XCTAssertEqual(coordinator.source, "- [x] hello")
        XCTAssertTrue(view.string.contains("☑"))
        view.onCheckbox?( (view.string as NSString).range(of: "☑").location )
        XCTAssertEqual(coordinator.source, "- [ ] hello")
    }
    func testUTF16MappingAtHiddenHeadingAndMathBoundaries() {
        let map = MarkdownOffsetMap(source: "# 🪴 Heading", display: "🪴 Heading")
        XCTAssertEqual(map.sourceRange(NSRange(location: 0, length: 2)), NSRange(location: 2, length: 2))
        XCTAssertEqual(map.displayRange(NSRange(location: 2, length: 2)), NSRange(location: 0, length: 2))
    }
    func testCheckboxMarkerMapsTheWholeSourceToken() {
        let map = MarkdownOffsetMap(source: "- [ ] hello", display: "☐ hello")
        XCTAssertEqual(map.sourceRange(NSRange(location: 0, length: 2)), NSRange(location: 0, length: 6))
        XCTAssertEqual(map.displayRange(NSRange(location: 6, length: 5)), NSRange(location: 2, length: 5))
        XCTAssertEqual(MarkdownOffsetMap(source: "- [ ] ", display: "☐ ").sourceRange(NSRange(location: 0, length: 2)), NSRange(location: 0, length: 6))
    }
    func testCodeFenceEndCaretStaysInsideTheBody() {
        let source = "```cpp\nhello\n```"
        guard let block = JournalCode.blocks(in: source).first else {
            return XCTFail("expected a code block")
        }
        let display = (source as NSString).substring(with: block.innerRange)
        let map = MarkdownOffsetMap(source: source, display: display)
        let lastLine = display.utf16.count - 1
        let sourceCaret = map.sourceRange(NSRange(location: lastLine, length: 0))
        XCTAssertEqual(sourceCaret.location, NSMaxRange(block.innerRange) - 1)
        XCTAssertLessThan(sourceCaret.location, block.closeRange.location)
        let after = map.sourceRange(NSRange(location: display.utf16.count, length: 0))
        XCTAssertEqual(after.location, NSMaxRange(block.range))
    }
    func testEmptyCodeFenceMapsCaretOntoTheInnerLine() {
        let source = "```cpp\n\n```"
        guard let block = JournalCode.blocks(in: source).first else {
            return XCTFail("expected a code block")
        }
        let display = (source as NSString).substring(with: block.innerRange)
        let map = MarkdownOffsetMap(source: source, display: display)
        let inside = NSRange(location: NSMaxRange(block.openRange), length: 0)
        XCTAssertEqual(map.displayRange(inside).location, 0)
        XCTAssertEqual(map.sourceRange(NSRange(location: 0, length: 0)), inside)
    }
    @MainActor func testCodeBlockOnTheFirstLineKeepsFencesAndLeavesToFollowingText() async throws {
        let (coordinator, view) = try liveEditor("")
        for character in "```cpp" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        view.insertNewline(nil)
        XCTAssertTrue(view.string.hasPrefix("```cpp"))
        XCTAssertEqual(coordinator.source, "```cpp\n\n```\n")
        for character in "first" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        XCTAssertEqual(coordinator.source, "```cpp\nfirst\n```\n")
        XCTAssertTrue(view.string.contains("```cpp"))
        guard let close = JournalCode.blocks(in: coordinator.source).first?.closeRange else {
            return XCTFail("expected a closed fence")
        }
        view.setSelectedRange(NSRange(location: close.location, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        view.insertNewline(nil)
        XCTAssertFalse(view.string.contains("```"))
        view.insertText("after", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.source, "```cpp\nfirst\n```\nafter")
        let after = (view.string as NSString).range(of: "after")
        XCTAssertNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: after.location, effectiveRange: nil))
        let first = (view.string as NSString).range(of: "first")
        XCTAssertEqual(view.textStorage?.attribute(JournalRichText.codeBlock, at: first.location, effectiveRange: nil) as? String, "cpp")
    }
    @MainActor func testTypingAtTheEndOfPreviewedCodeDoesNotCorruptTheFence() async throws {
        let (coordinator, view) = try liveEditor("```cpp\nhello\n```")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        XCTAssertFalse(view.string.contains("```"))
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertFalse(coordinator.source.contains("X```"))
        XCTAssertTrue(coordinator.source.hasPrefix("```cpp\nhello"))
        XCTAssertTrue(coordinator.source.contains("```"))
        XCTAssertFalse(view.string.contains("```"))
    }
    @MainActor func testReturnOnAnEmptyFenceThenTypeKeepsThePill() async throws {
        let (coordinator, view) = try liveEditor("")
        for character in "```cpp" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "```cpp\n\n```\n")
        XCTAssertTrue(view.string.contains("```cpp"))
        XCTAssertNotNil(view.textStorage?.attribute(JournalRichText.codeBlock, at: 0, effectiveRange: nil))
        for character in "where did it go" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        XCTAssertEqual(coordinator.source, "```cpp\nwhere did it go\n```\n")
        XCTAssertTrue(view.string.contains("```"))
        view.insertNewline(nil)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.liveSession?.selectionChanged(in: view)
        view.insertText("h", replacementRange: view.selectedRange())
        XCTAssertFalse(coordinator.source.contains("h```"))
        XCTAssertFalse(view.string.contains("```"))
        XCTAssertTrue(coordinator.source.contains("where did it go"))
        XCTAssertTrue(coordinator.source.contains("```"))
    }
}
