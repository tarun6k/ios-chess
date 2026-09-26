import XCTest

final class AdaptiveChessUITests: XCTestCase {
    /// Boots straight into the home screen (the `home` debug scenario continues as guest when
    /// no name is stored) so the check does not depend on what the simulator has persisted.
    @MainActor
    func testLaunchShowsHomeTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--scenario", "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chess"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["nav-home"].isSelected)
    }
}
