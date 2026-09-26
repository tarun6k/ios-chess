import XCTest

final class AdaptiveChessUITests: XCTestCase {
    @MainActor
    func testLaunchShowsPlaceholderTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Chess"].waitForExistence(timeout: 10))
    }
}
