import Foundation
import Observation

@MainActor @Observable
package final class ICloudSync {
    package private(set) var status = "iCloud sync is off"
    package private(set) var enabled: Bool
    private let store: Store
    private let localURL: URL
    private var ledger: SyncLedger
    private var timer: Timer?
    private var syncing = false
    private var accountToken: Data?
    private let defaults: UserDefaults

    package init(store: Store, defaults: UserDefaults = .standard) throws {
        self.store = store
        self.defaults = defaults
        enabled = defaults.bool(forKey: "iCloudSyncEnabled")
        localURL = store.location.deletingLastPathComponent().appendingPathComponent("SyncLedger.json")
        if FileManager.default.fileExists(atPath: localURL.path) {
            ledger = try JSONDecoder().decode(SyncLedger.self, from: Data(contentsOf: localURL))
            guard ledger.version == 1 else { throw StorageError.message("Sync ledger requires a newer Opus version.") }
        } else { ledger = SyncLedger() }
        try ledger.capture(store.state)
        try persist()
        store.didSave = { [weak self] in self?.capture() }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    package func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "iCloudSyncEnabled")
        status = value ? "Waiting for iCloud" : "iCloud sync is off"
        if value { Task { await sync() } }
    }
    private func persist() throws { try JSONEncoder().encode(ledger).write(to: localURL, options: .atomic) }
    private func capture() {
        do { try ledger.capture(store.state); try persist() }
        catch { status = "Sync error: \(error.localizedDescription)" }
    }

    package func sync() async {
        guard enabled, !syncing else { return }
        syncing = true
        defer { syncing = false }
        // Resolving the ubiquity container may block; do it away from the UI.
        let root = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        guard enabled else { return }
        guard let token = FileManager.default.ubiquityIdentityToken,
              let root else { status = "iCloud unavailable — check account, Drive, and signing"; return }
        do {
            let identity = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
            let accountURL = localURL.deletingLastPathComponent().appendingPathComponent("SyncAccount.data")
            let previousIdentity = accountToken ?? (try? Data(contentsOf: accountURL))
            guard previousIdentity == nil || previousIdentity == identity else {
                setEnabled(false)
                status = "iCloud account changed. Use the original account to protect your data."
                return
            }
            accountToken = identity
            try identity.write(to: accountURL, options: .atomic)
            let directory = root.appendingPathComponent("Documents/OpusSync", isDirectory: true)
            let downloaded = try await Task.detached { try CloudFiles.read(directory) }.value
            guard enabled else { return }
            guard let currentToken = FileManager.default.ubiquityIdentityToken,
                  try NSKeyedArchiver.archivedData(withRootObject: currentToken, requiringSecureCoding: false) == identity else {
                setEnabled(false)
                status = "iCloud account changed during sync. Use the original account."
                return
            }
            // Local edits may have happened while the files were downloading.
            // Merge into the newest ledger, never the state captured before await.
            var merged = ledger
            for remote in downloaded.ledgers { try merged.merge(remote) }
            // Commit locally before publishing. A failed database write must never
            // advertise a state this device could not load.
            let next = try merged.snapshot()
            try store.applySynced(next)
            ledger = merged
            try persist()
            let destination = directory.appendingPathComponent(ledger.device + ".json")
            let data = try JSONEncoder().encode(ledger)
            try await Task.detached { try CloudFiles.write(data, to: destination) }.value
            guard enabled else { return }
            status = downloaded.waiting ? "Downloading iCloud changes…" : "iCloud checked at \(Date().formatted(date: .omitted, time: .shortened))"

        } catch { status = "Sync error: \(error.localizedDescription)" }
    }
}

/// Coordinated cloud disk access runs outside the main actor. A device writes
/// only its own file; unresolved versions are merged without discarding them.
private enum CloudFiles {
    struct ReadResult: Sendable {
        var ledgers: [SyncLedger] = []
        var waiting = false
    }
    static func read(_ directory: URL) throws -> ReadResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var result = ReadResult()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]) {
            // macOS may enumerate evicted documents as hidden .name.icloud
            // placeholders rather than the logical document URL.
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let logicalName = String(name.dropFirst().dropLast(".icloud".count))
                try FileManager.default.startDownloadingUbiquitousItem(at: directory.appendingPathComponent(logicalName))
                result.waiting = true
                continue
            }
            guard url.pathExtension == "json" else { continue }
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let download = values.ubiquitousItemDownloadingStatus, download != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                result.waiting = true
                continue
            }
            var coordinationError: NSError?
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                do {
                    result.ledgers.append(try JSONDecoder().decode(SyncLedger.self, from: Data(contentsOf: coordinated)))
                    for conflict in NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinated) ?? [] {
                        result.ledgers.append(try JSONDecoder().decode(SyncLedger.self, from: Data(contentsOf: conflict.url)))
                    }
                } catch { readError = error }
            }
            if let error = coordinationError ?? readError as NSError? { throw error }
        }
        return result
    }
    static func write(_ data: Data, to destination: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
    }
}
