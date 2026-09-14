import Foundation
import XCTest
import OpusCore
@testable import Opus

final class FixRegressionTests: XCTestCase {
    @MainActor func testSavingUndatedProgressKeepsDeadlineEmpty() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Database(url: folder.appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let task = StudyTask(title: "Reading", kind: .progress, current: 5)
        store.save(task)
        WorkItemEditor(store: store, source: .task(task)).save()
        XCTAssertNil(store.state.tasks.first?.due)
        XCTAssertNil(try database.load().tasks.first?.due)
    }

    @MainActor func testCompletionIsPersistedBeforeRowDisappears() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Database(url: folder.appendingPathComponent("test.sqlite"))
        let store = try Store(database: database)
        let task = StudyTask(title: "Finish")
        store.save(task)
        TaskLine(store: store, task: task, selected: false, openDetails: {}).toggleComplete()
        XCTAssertTrue(try XCTUnwrap(database.load().tasks.first).completed)
        store.undo()
        XCTAssertFalse(try XCTUnwrap(database.load().tasks.first).completed)
    }

    @MainActor func testUpdaterStagesAndRollsBackWithoutLosingInstalledBundle() async throws {
        for scenario in ["success", "copy-failure", "invalid-bundle", "swap-failure"] {
            let fm = FileManager.default
            let folder = fm.temporaryDirectory.appendingPathComponent("Update test \(UUID().uuidString)")
            defer { try? fm.removeItem(at: folder) }
            let source = folder.appendingPathComponent("new.app")
            let destination = folder.appendingPathComponent("installed.app")
            let marker = folder.appendingPathComponent("marker")
            for (bundle, text) in [(source, "new"), (destination, "old")] {
                try fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
                try text.write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
                let executable = bundle.appendingPathComponent("Contents/MacOS/Opus")
                try text.write(to: executable, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            }
            var script = AppUpdater.replacementScript.replacingOccurrences(of: "/usr/bin/open", with: "/usr/bin/true")
            if scenario == "copy-failure" {
                // Inject a failed copy after staging has begun.
                script = script.replacingOccurrences(of: "/usr/bin/ditto", with: "/usr/bin/false")
            } else if scenario == "invalid-bundle" {
                try fm.removeItem(at: source.appendingPathComponent("Contents/MacOS/Opus"))
            } else if scenario == "swap-failure" {
                script = script.replacingOccurrences(of: "/bin/mv \"$staged\" \"$dest\"", with: "/usr/bin/false")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script, "--", "99999999", source.path, destination.path, "1.2.3", marker.path]
            try process.run()
            process.waitUntilExit()
            let succeeded = scenario == "success"
            XCTAssertEqual(process.terminationStatus == 0, succeeded, scenario)
            XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Contents/MacOS/Opus"), encoding: .utf8), succeeded ? "new" : "old", scenario)
            XCTAssertEqual(fm.fileExists(atPath: marker.path), succeeded, scenario)
            XCTAssertFalse(try fm.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".opus-update") }, scenario)
        }
    }
}
