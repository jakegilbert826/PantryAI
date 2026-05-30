import XCTest

/// Exercises the Household/Settings screen interactions that don't require a
/// network or API key.
final class SettingsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication.pantry(["-skipOnboarding", "-resetDefaults"])
        app.launch()
        app.buttons["Household"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
        return app
    }

    func testSettingsShowsCoreSections() {
        let app = openSettings()
        XCTAssertTrue(app.staticTexts["PEOPLE IN HOUSEHOLD"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["DANGER"].exists)
    }

    func testClearInventoryShowsConfirmationAlert() {
        let app = openSettings()
        let clearButton = app.buttons["Clear all inventory"]
        clearButton.tapWhenReady()

        let alert = app.alerts["Clear all inventory?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        // Cancel leaves everything intact.
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }
}
