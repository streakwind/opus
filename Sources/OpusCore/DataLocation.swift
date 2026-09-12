import Foundation

package enum DataLocation {
    package static func linux(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let custom = environment["OPUS_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom).appendingPathComponent("Opus.sqlite")
        }
        let root: URL
        if let xdg = environment["XDG_DATA_HOME"], xdg.hasPrefix("/") {
            root = URL(fileURLWithPath: xdg)
        } else {
            root = home.appendingPathComponent(".local/share", isDirectory: true)
        }
        return root.appendingPathComponent("opus/Opus.sqlite")
    }
}
