import Foundation

package enum AppChannel: String, Equatable {
    case macOS
    case linux
    package var assetName: String {
        switch self {
        case .macOS: "Opus-macOS.zip"
        case .linux: "Opus-linux-x86_64.tar.gz"
        }
    }
}

package struct AppVersion: Comparable, Equatable {
    package var major: Int
    package var minor: Int
    package var patch: Int
    package var original: String
    package init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let core = withoutV.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? withoutV
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        major = parts[0]
        minor = parts[1]
        patch = parts.count > 2 ? parts[2] : 0
        original = withoutV
    }
    package static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

package struct AppUpdateOffer: Equatable, Sendable {
    package var version: String
    package var downloadURL: String
    package var pageURL: String
}

package enum AppUpdate {
    package static let repository = "streakwind/opus"
    package static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    package static func offer(from data: Data, current: String, channel: AppChannel) throws -> AppUpdateOffer? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let remote = AppVersion(release.tagName), let local = AppVersion(current) else { return nil }
        guard remote > local else { return nil }
        guard let asset = release.assets.first(where: { $0.name == channel.assetName }) else {
            throw AppUpdateError.missingAsset
        }
        return AppUpdateOffer(version: remote.original, downloadURL: asset.browserDownloadUrl, pageURL: release.htmlUrl)
    }
}

package enum AppUpdateError: Error, Equatable {
    case missingAsset
    case badResponse
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var htmlUrl: String
    var assets: [Asset]
    struct Asset: Decodable {
        var name: String
        var browserDownloadUrl: String
    }
}
