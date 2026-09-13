import XCTest
@testable import OpusCore

final class AppUpdateTests: XCTestCase {
    func testVersionOrderingIgnoresVPrefixAndComparesNumerically() {
        XCTAssertEqual(AppVersion("v0.5.3"), AppVersion("0.5.3"))
        XCTAssertTrue(AppVersion("0.5.3")! > AppVersion("0.5.2")!)
        XCTAssertTrue(AppVersion("0.5.3")! > AppVersion("0.2.0")!)
        XCTAssertFalse(AppVersion("0.5.3")! > AppVersion("0.5.3")!)
        XCTAssertTrue(AppVersion("1.0.0")! > AppVersion("0.9.9")!)
        XCTAssertNil(AppVersion("nope"))
    }

    func testLatestReleaseOffersNewerMacBuildAndIgnoresCurrentVersion() throws {
        let data = Data("""
        {
          "tag_name": "v0.5.4",
          "html_url": "https://github.com/streakwind/opus/releases/tag/v0.5.4",
          "assets": [
            {"name": "Opus-linux-x86_64.tar.gz", "browser_download_url": "https://example.com/linux"},
            {"name": "Opus-macOS.zip", "browser_download_url": "https://example.com/mac"}
          ]
        }
        """.utf8)
        let offer = try AppUpdate.offer(from: data, current: "0.5.3", channel: .macOS)
        XCTAssertEqual(offer?.version, "0.5.4")
        XCTAssertEqual(offer?.downloadURL, "https://example.com/mac")
        XCTAssertNil(try AppUpdate.offer(from: data, current: "0.5.4", channel: .macOS))
        XCTAssertNil(try AppUpdate.offer(from: data, current: "0.6.0", channel: .macOS))
        XCTAssertEqual(try AppUpdate.offer(from: data, current: "0.5.3", channel: .linux)?.downloadURL, "https://example.com/linux")
    }

    func testMissingChannelAssetFailsInsteadOfSilentlySkipping() {
        let data = Data("""
        {"tag_name":"v1.0.0","html_url":"https://example.com","assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes"}]}
        """.utf8)
        XCTAssertThrowsError(try AppUpdate.offer(from: data, current: "0.1.0", channel: .macOS)) { error in
            XCTAssertEqual(error as? AppUpdateError, .missingAsset)
        }
    }
}
