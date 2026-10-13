import OpusCore
import SwiftUI
import AppKit

public struct OpusApplication: App {
    @State private var store: Store?
    @State private var sync: ICloudSync?
    @Environment(\.scenePhase) private var scenePhase
    @State private var startupError: String?
    public init() {
        MathRenderer.prepareFonts()
        do {
            let root: URL
            if let custom = ProcessInfo.processInfo.environment["OPUS_DATA_DIR"] { root = URL(fileURLWithPath: custom) }
            else { root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Opus", isDirectory: true) }
            let opened = try Store(database: Database(url: root.appendingPathComponent("Opus.sqlite")))
            _store = State(initialValue: opened)
            do { _sync = State(initialValue: try ICloudSync(store: opened)) }
            catch { opened.error = "iCloud sync could not start: \(error.localizedDescription)" }
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    public var body: some Scene {
        WindowGroup {
            if let store {
                ContentView(store: store, sync: sync).background(WindowChrome()).frame(minWidth: 850, minHeight: 600)
                    .task { await sync?.sync() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { store.refreshOccurrences(); Task { await sync?.sync() } }
                    }
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
