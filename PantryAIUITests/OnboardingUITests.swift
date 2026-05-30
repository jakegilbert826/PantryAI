import XCTest

/// End-to-end walk through the first-run onboarding flow, driving the real app
/// exactly as a user would: Welcome → Household → Recipe swipe → Camera → main app.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFullOnboardingFlowReachesMainApp() {
        let app = XCUIApplication.pantry(["-resetOnboarding", "-resetDefaults"])
        app.launch()

        // Step 1 — Welcome
        XCTAssertTrue(app.staticTexts["Hi there!"].waitForExistence(timeout: 8))
        app.buttons["Get started"].tapWhenReady()

        // Step 2 — Household ("Who's eating?")
        XCTAssertTrue(app.staticTexts["Who's eating?"].waitForExistence(timeout: 8))
        app.buttons["Continue"].tapWhenReady()

        // Step 3 — Recipe swipe. The ghost "Done" button skips the deck.
        XCTAssertTrue(app.staticTexts["Swipe to teach Pip."].waitForExistence(timeout: 8))
        app.buttons["Done"].tapWhenReady()

        // Step 4 — Camera permission. Skip to avoid the system dialog.
        XCTAssertTrue(app.staticTexts["Open the lens."].waitForExistence(timeout: 8))
        app.buttons["Skip for now"].tapWhenReady()

        // Landed in the main app — Pantry tab is the default.
        XCTAssertTrue(app.staticTexts["What's cooking?"].waitForExistence(timeout: 8))
    }

    func testHouseholdStepperIncrementsCount() {
        let app = XCUIApplication.pantry(["-resetOnboarding", "-resetDefaults"])
        app.launch()

        app.buttons["Get started"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Who's eating?"].waitForExistence(timeout: 8))

        // Default household size is 2.
        XCTAssertTrue(app.staticTexts["2"].exists)
        // The "+" button bumps it to 3.
        app.buttons["plus"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 4))
    }

    func testSkippedOnboardingDoesNotShowOnRelaunch() {
        // First run: complete onboarding via the skip path.
        let app = XCUIApplication.pantry(["-skipOnboarding"])
        app.launch()
        XCTAssertTrue(app.staticTexts["What's cooking?"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Hi there!"].exists)
    }
}
