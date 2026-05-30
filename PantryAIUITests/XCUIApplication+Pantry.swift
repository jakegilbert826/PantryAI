import XCTest

extension XCUIApplication {
    /// Launches the app in UI-test mode with the given extra arguments already
    /// prefixed by `-uitests` so `TestSupport` picks them up.
    static func pantry(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitests"] + arguments
        return app
    }
}

extension XCUIElement {
    /// Tap once the element is actually on screen, failing the test otherwise.
    @discardableResult
    func tapWhenReady(timeout: TimeInterval = 8, file: StaticString = #file, line: UInt = #line) -> Bool {
        guard waitForExistence(timeout: timeout) else {
            XCTFail("Element \(self) never appeared", file: file, line: line)
            return false
        }
        tap()
        return true
    }
}
