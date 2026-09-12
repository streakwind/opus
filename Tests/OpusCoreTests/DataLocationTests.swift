import XCTest
@testable import OpusCore

final class DataLocationTests: XCTestCase {
    func testLinuxDataLocationUsesXDGAndIgnoresRelativeXDG() {
        let home = URL(fileURLWithPath: "/home/example")
        XCTAssertEqual(DataLocation.linux(environment: [:], home: home).path, "/home/example/.local/share/opus/Opus.sqlite")
        XCTAssertEqual(DataLocation.linux(environment: ["XDG_DATA_HOME": "/data"], home: home).path, "/data/opus/Opus.sqlite")
        XCTAssertEqual(DataLocation.linux(environment: ["XDG_DATA_HOME": "relative"], home: home).path, "/home/example/.local/share/opus/Opus.sqlite")
        XCTAssertEqual(DataLocation.linux(environment: ["OPUS_DATA_DIR": "/isolated", "XDG_DATA_HOME": "/data"], home: home).path, "/isolated/Opus.sqlite")
    }
}
