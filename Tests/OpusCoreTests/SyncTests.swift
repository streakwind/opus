import XCTest
@testable import OpusCore

final class SyncTests: XCTestCase {
    func testIndependentOfflineEditsConverge() throws {
        var initial = Snapshot()
        initial.tasks = [StudyTask(id: "a", title: "A"), StudyTask(id: "b", title: "B")]
        var left = SyncLedger()
        try left.capture(initial, now: Date(timeIntervalSince1970: 1))
        var right = left
        right.device = "second-device"
        var a = initial; a.tasks[0].title = "A edited"
        var b = initial; b.tasks[1].title = "B edited"
        try left.capture(a, now: Date(timeIntervalSince1970: 2))
        try right.capture(b, now: Date(timeIntervalSince1970: 2))
        let originalLeft = left
        try left.merge(right); try right.merge(originalLeft)
        XCTAssertEqual(left.records, right.records)
        XCTAssertEqual(try left.snapshot().tasks.map(\.title), ["A edited", "B edited"])
    }
    func testDeletionSurvivesStaleDeviceAndLedgerReload() throws {
        var state = Snapshot(); state.tasks = [StudyTask(id: "a", title: "A")]
        var ledger = SyncLedger(); try ledger.capture(state)
        let stale = ledger
        state.tasks.removeAll(); try ledger.capture(state)
        ledger = try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(ledger))
        try ledger.merge(stale)
        XCTAssertTrue(try ledger.snapshot().tasks.isEmpty)
        XCTAssertNil(ledger.records["tasks/a"]?.payload)
    }
    func testTieBreakAndForeignKeyRepair() throws {
        var state = Snapshot(); state.courses = [Course(id: "c", name: "List")]
        state.tasks = [StudyTask(id: "t", courseID: "c", title: "Task")]
        var a = SyncLedger(); a.device = "a"; try a.capture(state, now: Date(timeIntervalSince1970: 1))
        var b = a; b.device = "b"
        state.tasks[0].title = "B"; try b.capture(state, now: Date(timeIntervalSince1970: 2))
        state.tasks[0].title = "A"; state.courses = []; try a.capture(state, now: Date(timeIntervalSince1970: 2))
        try a.merge(b)
        XCTAssertEqual(try a.snapshot().tasks.first?.title, "B")
        XCTAssertNil(try a.snapshot().tasks.first?.courseID)
        XCTAssertThrowsError(try { var future = b; future.version = 2; try a.merge(future) }())
    }
    @MainActor func testOfflineRecurrenceGenerationUsesTheSameIDs() {
        var left = Snapshot()
        left.rules = [QuizRule(id: "rule", title: "Read", weekday: 2, itemKind: .task)]
        var right = left
        Store.generate(in: &left)
        Store.generate(in: &right)
        XCTAssertFalse(left.tasks.isEmpty)
        XCTAssertEqual(left.tasks.map(\.id), right.tasks.map(\.id))
    }
    @MainActor func testSyncClearsUndoAndPersistsWithoutFeedback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try Database(url: root.appendingPathComponent("test.sqlite"))
        let store = try Store(database: db)
        var callbacks = 0; store.didSave = { callbacks += 1 }
        store.save(StudyTask(title: "Local"))
        XCTAssertEqual(callbacks, 1)
        var remote = store.state; remote.tasks.append(StudyTask(title: "Remote"))
        try store.applySynced(remote)
        XCTAssertEqual(callbacks, 1)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try db.load().tasks.count, 2)
    }
}
