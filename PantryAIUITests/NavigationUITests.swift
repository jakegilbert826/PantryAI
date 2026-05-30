import XCTest

/// Drives the floating tab bar and asserts each destination renders. Launches
/// past onboarding so every test starts on the Pantry tab.
final class NavigationUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication.pantry(["-skipOnboarding"])
        app.launch()
        XCTAssertTrue(app.staticTexts["What's cooking?"].waitForExistence(timeout: 8),
            "app should open on the Pantry tab")
        return app
    }

    func testTabBarIsPresent() {
        let app = launchedApp()
        XCTAssertTrue(app.buttons["Pantry"].exists)
        XCTAssertTrue(app.buttons["Scan"].exists)
        XCTAssertTrue(app.buttons["Recipes"].exists)
        XCTAssertTrue(app.buttons["Household"].exists)
    }

    func testNavigateToRecipes() {
        let app = launchedApp()
        app.buttons["Recipes"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Pip is cooking"].waitForExistence(timeout: 8))
    }

    func testNavigateToHouseholdSettings() {
        let app = launchedApp()
        app.buttons["Household"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
    }

    func testNavigateBackToPantry() {
        let app = launchedApp()
        app.buttons["Household"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
        app.buttons["Pantry"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["What's cooking?"].waitForExistence(timeout: 8))
    }

    func testNavigateToScanShowsCaptureScreen() {
        let app = launchedApp()
        app.buttons["Scan"].tapWhenReady()
        // The simulator has no camera, so an init alert may appear — dismiss it.
        let cameraAlertOK = app.alerts.buttons["OK"]
        if cameraAlertOK.waitForExistence(timeout: 3) {
            cameraAlertOK.tap()
        }
        XCTAssertTrue(app.staticTexts["Found 0 photos"].waitForExistence(timeout: 8))
    }
}
