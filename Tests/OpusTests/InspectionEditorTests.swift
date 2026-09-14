import AppKit
import SwiftUI
import XCTest
import OpusCore
@testable import Opus

final class InspectionEditorTests: XCTestCase {
    @MainActor func testReturnIntentionallyInsertsAfterSelection() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(database: Database(url: folder.appendingPathComponent("test.sqlite")))
        let parent = JournalNativeEditor(markdown: .constant("hello world"), store: store, day: Day.today, focusRequest: 0, pendingEmbed: .constant(nil), onTaskCommand: { _ in }, onOpen: { _ in }, live: true)
        let coordinator = parent.makeCoordinator()
        let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.delegate = coordinator
        coordinator.load("hello world", in: view)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        coordinator.liveSession?.selectionChanged(in: view)
        view.insertNewline(nil)
        XCTAssertEqual(coordinator.source, "hello\n world")
    }
}
