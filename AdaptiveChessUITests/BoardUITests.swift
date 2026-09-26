import XCTest

/// Drives the DEBUG board gallery: pieces move by tap-tap and by drag, and the squares expose
/// the same VoiceOver names as the TS board.
final class BoardUITests: XCTestCase {
    @MainActor
    private func launchGallery(page: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--board-gallery", "\(page)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chess"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func square(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func testTapTapMovesAPawn() {
        let app = launchGallery(page: 0)
        let from = square(app, "d2, white pawn")
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.tap()
        square(app, "d4").tap()
        XCTAssertTrue(square(app, "d4, white pawn").waitForExistence(timeout: 5))
        XCTAssertTrue(square(app, "d2").exists)
        XCTAssertTrue(app.staticTexts["Black to move"].exists)
    }

    @MainActor
    func testDragAndDropMovesAPawn() {
        let app = launchGallery(page: 0)
        let from = square(app, "e2, white pawn")
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.press(forDuration: 0.2, thenDragTo: square(app, "e4"))
        XCTAssertTrue(square(app, "e4, white pawn").waitForExistence(timeout: 5))
        XCTAssertTrue(square(app, "e2").exists)
    }

    @MainActor
    func testIllegalDropSnapsBack() {
        let app = launchGallery(page: 0)
        let from = square(app, "e2, white pawn")
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.press(forDuration: 0.2, thenDragTo: square(app, "e5"))
        XCTAssertTrue(square(app, "e2, white pawn").waitForExistence(timeout: 5))
        XCTAssertFalse(square(app, "e5, white pawn").exists)
    }

    @MainActor
    func testPromotionDialogOffersFourPieces() {
        let app = launchGallery(page: 4)
        XCTAssertTrue(app.staticTexts["Promote to"].waitForExistence(timeout: 5))
        for name in ["queen", "rook", "bishop", "knight"] {
            XCTAssertTrue(app.buttons[name].exists, "\(name) button missing")
        }
        app.buttons["knight"].tap()
        XCTAssertTrue(square(app, "g8, white knight").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Promote to"].exists)
    }
}
