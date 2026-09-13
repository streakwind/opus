import Foundation
import AppKit
import OpusCore
import Observation

@MainActor @Observable
final class AppUpdater {
    enum Status: Equatable {
        case idle
        case checking
        case current
        case available(AppUpdateOffer)
        case working(String)
        case failed(String)
    }

    var status: Status = .idle
    let currentVersion: String
    private let channel: AppChannel
    private var inFlight = false

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        channel: AppChannel = .macOS
    ) {
        self.currentVersion = currentVersion
        self.channel = channel
    }

    func check() async {
        guard !inFlight else { return }
        inFlight = true
        status = .checking
        defer { inFlight = false }
        do {
            var request = URLRequest(url: AppUpdate.latestReleaseURL)
            request.setValue("Opus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                status = .failed(http.statusCode == 403 ? "GitHub rate-limited the check. Try again in a bit." : "Couldn't check for updates.")
                return
            }
            if let offer = try AppUpdate.offer(from: data, current: currentVersion, channel: channel) {
                status = .available(offer)
            } else {
                status = .current
            }
        } catch AppUpdateError.missingAsset {
            status = .failed("This release doesn't include a Mac build yet.")
        } catch {
            status = .failed("Couldn't reach GitHub.")
        }
    }

    func install(_ offer: AppUpdateOffer) async {
        guard !inFlight else { return }
        inFlight = true
        status = .working("Downloading Opus \(offer.version)…")
        defer { inFlight = false }
        do {
            guard let url = URL(string: offer.downloadURL) else {
                status = .failed("The download link is missing.")
                return
            }
            let (temp, _) = try await URLSession.shared.download(from: url)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("OpusUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("Opus-macOS.zip")
            if FileManager.default.fileExists(atPath: zip.path) {
                try FileManager.default.removeItem(at: zip)
            }
            try FileManager.default.moveItem(at: temp, to: zip)
            status = .working("Preparing Opus \(offer.version)…")
            let extract = work.appendingPathComponent("extract", isDirectory: true)
            try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, extract.path])
            guard let app = findOpusApp(in: extract) else {
                status = .failed("The download didn't contain Opus.app.")
                return
            }
            let dest = Bundle.main.bundleURL
            guard dest.pathExtension == "app" else {
                reveal(app, version: offer.version)
                return
            }
            guard FileManager.default.isWritableFile(atPath: dest.path) else {
                reveal(app, version: offer.version)
                return
            }
            status = .working("Installing Opus \(offer.version)…")
            try launchReplacer(from: app, replacing: dest)
            NSApplication.shared.terminate(nil)
        } catch {
            status = .failed("Couldn't install the update.")
        }
    }

    private func reveal(_ app: URL, version: String) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Opus.app")
        try? FileManager.default.removeItem(at: downloads)
        do {
            try FileManager.default.copyItem(at: app, to: downloads)
            NSWorkspace.shared.activateFileViewerSelecting([downloads])
            status = .failed("Opus \(version) is in Downloads. Replace the current app, then reopen it.")
        } catch {
            status = .failed("Couldn't save the update. Open the GitHub release instead.")
        }
    }

    private func findOpusApp(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var checked = 0
        for case let url as URL in enumerator {
            checked += 1
            if checked > 80 { break }
            guard url.pathExtension == "app" else { continue }
            enumerator.skipDescendants()
            let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            if plist?["CFBundleIdentifier"] as? String == "com.ruben.opus" { return url }
            if fm.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/Opus").path) { return url }
        }
        return nil
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.badResponse
        }
    }

    private func launchReplacer(from source: URL, replacing destination: URL) throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("opus-replace-\(UUID().uuidString).sh")
        let body = """
        #!/bin/bash
        trap '' HUP
        pid="$1"
        src="$2"
        dest="$3"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/sleep 0.4
        /bin/rm -rf "$dest"
        /usr/bin/ditto "$src" "$dest"
        /usr/bin/xattr -cr "$dest" || true
        /usr/bin/open "$dest"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "trap '' HUP; nohup /bin/bash \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &",
            "--",
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            source.path,
            destination.path
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppUpdateError.badResponse }
    }
}
