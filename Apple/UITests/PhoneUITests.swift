import XCTest

final class PhoneUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testTabsAndTaskCreation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OPUS_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        app.buttons["Task"].tap()
        let title = app.textFields["Title"].firstMatch.exists ? app.textFields["Title"].firstMatch : app.textViews.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Phone smoke task")
        app.buttons["Save"].tap()
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.staticTexts["Phone smoke task"].waitForExistence(timeout: 5))
        attach(app, "Tasks")
        for tab in ["Calendar", "Journal", "Rhythm", "Today"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            attach(app, tab)
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Sync with iCloud"].exists)
        attach(app, "Settings")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
