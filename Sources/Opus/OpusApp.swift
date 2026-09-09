import SwiftUI
import AppKit

@main
struct OpusApp: App {
    @State private var store: Store?
    @State private var startupError: String?
    init() {
        do {
            let root: URL
            if let custom = ProcessInfo.processInfo.environment["OPUS_DATA_DIR"] { root = URL(fileURLWithPath: custom) }
            else { root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Opus", isDirectory: true) }
            _store = State(initialValue: try Store(database: Database(url: root.appendingPathComponent("Opus.sqlite"))))
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        WindowGroup {
            if let store {
                ContentView(store: store).frame(minWidth: 850, minHeight: 600)
                    .onAppear {
                        if let url = Bundle.main.url(forResource: "OpusStack", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApplication.shared.applicationIconImage = icon }
                    }
            }
            else { ContentUnavailableView("Unable to open Opus", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "Unknown storage error")) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .undoRedo) {
                Button("Undo task change") { store?.undo() }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(store?.canUndo != true)
            }
        }
    }
}
