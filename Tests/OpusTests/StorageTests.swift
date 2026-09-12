import XCTest
import SwiftUI
import OpusCore
@testable import Opus

final class AppearanceTests: XCTestCase {
    func testCustomCourseHexColorsRoundTrip() {
        XCTAssertEqual(Course.hexColor("#112233").map(Course.hex(from:)), "#112233")
        XCTAssertEqual(Course.hex(from: Color(red: 1, green: 0, blue: 0.5)), "#FF0080")
        XCTAssertEqual(Course(name: "Y", color: "#FF0080").color, "#FF0080")
        XCTAssertEqual(Course.hex(from: Course(name: "Y", color: "#FF0080").tint), "#FF0080")
    }
}
