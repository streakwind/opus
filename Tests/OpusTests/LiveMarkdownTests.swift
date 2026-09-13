import AppKit
import SwiftUI
import XCTest
import OpusCore
@testable import Opus

final class LiveMarkdownTests: XCTestCase {
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
        XCTAssertTrue(view.string.contains("**bold** and $x^2$"))
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
    func testUTF16MappingAtHiddenHeadingAndMathBoundaries() {
        let map = MarkdownOffsetMap(source: "# 🪴 Heading", display: "🪴 Heading")
        XCTAssertEqual(map.sourceRange(NSRange(location: 0, length: 2)), NSRange(location: 2, length: 2))
        XCTAssertEqual(map.displayRange(NSRange(location: 2, length: 2)), NSRange(location: 0, length: 2))
    }
}
