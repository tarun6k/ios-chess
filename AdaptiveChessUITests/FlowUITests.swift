import XCTest

/// End-to-end flows through the real app: first launch, playing against the AI, draws, tabs,
/// puzzles, settings persistence and resuming after the process was killed. Every test starts
/// from a wiped store (`--reset-state`, DEBUG builds only) so the simulator's history does not
/// leak between runs.
final class FlowUITests: XCTestCase {
    /// Generous: a "Match" reply is capped at 2.4 s of search plus the 450 ms humanlike pause,
    /// but the debug build searches about ten times slower per node and the simulator is shared.
    private let aiReply: TimeInterval = 25

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: helpers

    @MainActor
    private func launch(reset: Bool = true, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["--reset-state"] : []) + arguments
        app.launch()
        return app
    }

    @MainActor
    private func square(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Taps the centre of a square. XCUITest reports squares that carry a coordinate label (the
    /// a-file and the first rank) as "not hittable" even though they are on screen and respond
    /// to touches, so squares are tapped by coordinate, which skips that check.
    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is not on screen", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// A move in the side panel's move list (`play-moves`); the cells are buttons labelled with
    /// the SAN, and the list is scoped so an empty board square with the same name ("e4")
    /// cannot match.
    @MainActor
    private func san(_ app: XCUIApplication, _ san: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "play-moves")
            .buttons.matching(NSPredicate(format: "label == %@", san)).firstMatch
    }

    /// Asserts that the move list shows `san`, naming what it does show when it does not.
    @MainActor
    private func expectMove(_ app: XCUIApplication, _ san: String, file: StaticString = #filePath, line: UInt = #line) {
        if self.san(app, san).waitForExistence(timeout: 3) { return }
        let shown = app.descendants(matching: .any).matching(identifier: "play-moves").buttons
            .allElementsBoundByIndex.map(\.label)
        XCTFail("the move list does not show \(san); it shows \(shown)", file: file, line: line)
    }

    /// A cell of a `SegmentedControl` (or any button) by the control's identifier and the cell's
    /// label — SwiftUI hands a container's identifier down to each of its child elements.
    @MainActor
    private func cell(_ app: XCUIApplication, _ id: String, _ label: String) -> XCUIElement {
        app.buttons.matching(identifier: id).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Scrolls the page (a drag that starts below the board, so it is never taken for a piece
    /// drag) until `element` can be tapped.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertTrue(element.isHittable, "\(element) never became hittable", file: file, line: line)
    }

    /// Tap-tap a move and wait for the piece to land.
    @MainActor
    private func move(_ app: XCUIApplication, _ piece: String, from: String, to: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        let origin = square(app, "\(from), \(piece)")
        XCTAssertTrue(origin.waitForExistence(timeout: 5), "\(from) does not hold a \(piece)", file: file, line: line)
        tap(origin, file: file, line: line)
        tap(square(app, to), file: file, line: line)
        XCTAssertTrue(square(app, "\(to), \(piece)").waitForExistence(timeout: 5), "\(piece) \(from)-\(to) was not played", file: file, line: line)
    }

    /// Plays White's move and waits until the AI has answered (the status returns to "White to move").
    @MainActor
    private func playAndAwaitReply(_ app: XCUIApplication, _ piece: String, from: String, to: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        move(app, piece, from: from, to: to, file: file, line: line)
        XCTAssertTrue(app.staticTexts["White to move"].waitForExistence(timeout: aiReply), "the AI did not reply to \(from)-\(to)", file: file, line: line)
    }

    @MainActor
    private func continueAsGuest(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 10))
        app.buttons["login-guest"].tap()
        XCTAssertTrue(app.buttons["home-start"].waitForExistence(timeout: 5))
    }

    /// Home → Start game with the current picks; lands on the play screen at the start position.
    @MainActor
    private func startGame(_ app: XCUIApplication) {
        reveal(app.buttons["home-start"], in: app)
        app.buttons["home-start"].tap()
        XCTAssertTrue(app.staticTexts["White to move"].waitForExistence(timeout: 5))
        XCTAssertTrue(square(app, "e2, white pawn").waitForExistence(timeout: 5))
    }

    // MARK: flows

    @MainActor
    func testFirstLaunchAsksForANameOnceOnly() {
        let app = launch()
        continueAsGuest(app)
        XCTAssertTrue(app.staticTexts["An opponent that learns you"].exists)
        XCTAssertTrue(app.buttons["nav-home"].isSelected)

        // Once chosen, the login screen never comes back.
        app.terminate()
        let again = launch(reset: false)
        XCTAssertTrue(again.buttons["home-start"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.staticTexts["What should we call you?"].exists)
    }

    @MainActor
    func testGuestPlaysAgainstTheAIAndResigns() {
        let app = launch()
        continueAsGuest(app)
        startGame(app)

        // Three moves that are legal whatever Black answers.
        playAndAwaitReply(app, "white pawn", from: "e2", to: "e4")
        playAndAwaitReply(app, "white knight", from: "b1", to: "c3")
        playAndAwaitReply(app, "white knight", from: "g1", to: "f3")
        expectMove(app, "e4")
        expectMove(app, "Nc3")
        expectMove(app, "Nf3")

        reveal(app.buttons["play-resign"], in: app)
        app.buttons["play-resign"].tap()

        // Game-over sheet
        XCTAssertTrue(app.staticTexts["AI wins"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Black wins by resignation"].exists)
        XCTAssertTrue(app.buttons["play-export-pgn"].exists)
        XCTAssertTrue(app.buttons["play-review"].exists, "six plies were played, so Review is offered")
        XCTAssertTrue(app.buttons["play-game-over-new"].exists)
        app.buttons["play-game-over-close"].tap()
        XCTAssertTrue(app.staticTexts["Black wins by resignation"].waitForExistence(timeout: 5), "the status line keeps the result")
        XCTAssertTrue(app.buttons["play-summary"].exists, "the sheet can be reopened")
        XCTAssertFalse(app.buttons["play-resign"].exists)

        // Review mode steps through the game.
        app.buttons["play-summary"].tap()
        XCTAssertTrue(app.buttons["play-review"].waitForExistence(timeout: 5))
        app.buttons["play-review"].tap()
        XCTAssertTrue(app.staticTexts["Review · move 3 of 3"].waitForExistence(timeout: 5))
        reveal(app.buttons["play-review-first"], in: app)
        app.buttons["play-review-first"].tap()
        XCTAssertTrue(app.staticTexts["Review · move 0 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(square(app, "e2, white pawn").exists, "the first position is the start position")
        app.buttons["play-review-back"].tap()
        XCTAssertTrue(app.staticTexts["Black wins by resignation"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDrawOfferInPassAndPlayIsDecidedByTheOtherSide() {
        let app = launch()
        continueAsGuest(app)
        cell(app, "home-mode", "2 players").tap()
        XCTAssertTrue(cell(app, "home-mode", "2 players").isSelected)
        startGame(app)
        move(app, "white pawn", from: "e2", to: "e4")
        XCTAssertTrue(app.staticTexts["Black to move"].waitForExistence(timeout: 5))

        reveal(app.buttons["play-draw"], in: app)
        app.buttons["play-draw"].tap()
        XCTAssertTrue(app.staticTexts["Draw offer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Black offers a draw. Does White accept?"].exists)
        app.buttons["play-draw-decline"].tap()
        XCTAssertFalse(app.staticTexts["Draw offer"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Black to move"].exists, "declining keeps the game going")

        app.buttons["play-draw"].tap()
        XCTAssertTrue(app.staticTexts["Draw offer"].waitForExistence(timeout: 5))
        app.buttons["play-draw-accept"].tap()
        XCTAssertTrue(app.staticTexts["Draw"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draw by agreement"].exists)
        XCTAssertFalse(app.buttons["play-review"].exists, "pass-and-play games are not reviewed")
    }

    @MainActor
    func testDrawOfferAgainstTheAIInTheOpeningIsDeclined() {
        let app = launch()
        continueAsGuest(app)
        startGame(app)
        playAndAwaitReply(app, "white pawn", from: "e2", to: "e4")
        reveal(app.buttons["play-draw"], in: app)
        XCTAssertEqual(app.buttons["play-draw"].label, "Offer draw")
        app.buttons["play-draw"].tap()
        // The AI answers a draw offer with a 1.5 s look at the position; level, it declines.
        XCTAssertFalse(app.staticTexts["Draw by agreement"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["White to move"].exists)
        XCTAssertTrue(app.buttons["play-resign"].exists, "the game is still on")
    }

    @MainActor
    func testEveryTabOpens() {
        let app = launch()
        continueAsGuest(app)

        app.buttons["nav-play"].tap()
        XCTAssertTrue(app.buttons["play-new-game"].waitForExistence(timeout: 5))
        XCTAssertTrue(square(app, "e2, white pawn").exists)
        XCTAssertTrue(app.buttons["nav-play"].isSelected)

        app.buttons["nav-puzzles"].tap()
        XCTAssertTrue(app.staticTexts["Challenges"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nav-puzzles"].isSelected)

        app.buttons["nav-stats"].tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nav-stats"].isSelected)

        app.buttons["nav-settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nav-settings"].isSelected)

        app.buttons["nav-home"].tap()
        XCTAssertTrue(app.buttons["home-start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nav-home"].isSelected)
    }

    @MainActor
    func testSolvingAPuzzleAwardsXP() {
        let app = launch()
        continueAsGuest(app)
        app.buttons["nav-puzzles"].tap()
        XCTAssertTrue(app.staticTexts["Challenges"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 solved · 0 XP"].exists)

        // "Back-rank strike": 6k1/5ppp/8/8/8/8/8/R3K3, Ra8 mates. (`firstMatch`: the card is also
        // the daily challenge on some days.)
        let card = app.buttons["puzzle-m1-backrank"].firstMatch
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(app.staticTexts["Back-rank strike"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["White mates in one."].exists)
        XCTAssertFalse(app.buttons["play-hint"].exists, "no hints in challenges")

        move(app, "white rook", from: "a1", to: "a8")
        XCTAssertTrue(app.staticTexts["Solved! Well done."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Solved · +10 XP"].exists)
        XCTAssertTrue(app.staticTexts["You win"].waitForExistence(timeout: 5), "mate also ends the game")
        app.buttons["play-game-over-close"].tap()

        app.buttons["nav-puzzles"].tap()
        XCTAssertTrue(app.staticTexts["Challenges"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 solved · 10 XP"].exists)
        XCTAssertTrue(app.staticTexts["White mates in one. Untimed · Solved ✓"].firstMatch.exists)
    }

    @MainActor
    func testSettingsPersistAcrossRelaunch() {
        let app = launch()
        continueAsGuest(app)
        app.buttons["nav-settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(cell(app, "setting-Coordinates", "On").isSelected, "coordinates default to on")
        XCTAssertTrue(cell(app, "setting-boardFlip", "Auto").isSelected)

        cell(app, "setting-Coordinates", "Off").tap()
        cell(app, "setting-boardFlip", "Black").tap()
        cell(app, "setting-Auto-queen", "On").tap()
        reveal(cell(app, "setting-Sounds", "Off"), in: app)
        cell(app, "setting-Sounds", "Off").tap()
        cell(app, "setting-Haptics", "Off").tap()
        XCTAssertTrue(cell(app, "setting-Sounds", "Off").isSelected)

        app.terminate()
        let again = launch(reset: false)
        again.buttons["nav-settings"].tap()
        XCTAssertTrue(again.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(cell(again, "setting-Coordinates", "Off").isSelected)
        XCTAssertTrue(cell(again, "setting-boardFlip", "Black").isSelected)
        XCTAssertTrue(cell(again, "setting-Auto-queen", "On").isSelected)
        reveal(cell(again, "setting-Sounds", "Off"), in: again)
        XCTAssertTrue(cell(again, "setting-Sounds", "Off").isSelected)
        XCTAssertTrue(cell(again, "setting-Haptics", "Off").isSelected)
        XCTAssertTrue(cell(again, "setting-Takebacks", "On").isSelected, "untouched settings keep their defaults")

        // The board honours them: flipped for Black means a1 is drawn above a8.
        again.buttons["nav-play"].tap()
        let a1 = square(again, "a1, white rook")
        XCTAssertTrue(a1.waitForExistence(timeout: 5))
        XCTAssertLessThan(a1.frame.minY, square(again, "a8, black rook").frame.minY)
        XCTAssertFalse(again.staticTexts["a"].exists, "no file labels without coordinates")
    }

    @MainActor
    func testGameResumesAfterTheAppWasKilled() {
        let app = launch()
        continueAsGuest(app)
        XCTAssertFalse(app.buttons["home-resume"].exists, "nothing to resume on a fresh start")
        startGame(app)
        playAndAwaitReply(app, "white pawn", from: "e2", to: "e4")

        app.terminate()
        let again = launch(reset: false)
        XCTAssertTrue(again.buttons["home-resume"].waitForExistence(timeout: 10))
        XCTAssertTrue(again.staticTexts["1 move played"].exists)
        again.buttons["home-resume"].tap()
        XCTAssertTrue(square(again, "e4, white pawn").waitForExistence(timeout: 5))
        XCTAssertTrue(again.staticTexts["White to move"].exists)
        expectMove(again, "e4")
        XCTAssertFalse(square(again, "e2, white pawn").exists)

        // The resumed game plays on.
        playAndAwaitReply(again, "white knight", from: "b1", to: "c3")
        expectMove(again, "Nc3")
    }

    @MainActor
    func testTheUIStaysResponsiveWhileTheAIThinks() {
        let app = launch()
        continueAsGuest(app)
        cell(app, "home-level", "Push me").tap()
        XCTAssertTrue(cell(app, "home-level", "Push me").isSelected)
        startGame(app)
        move(app, "white pawn", from: "d2", to: "d4")

        // Search runs on the engine actor, so the tabs switch instantly mid-think.
        let switched = Date()
        app.buttons["nav-stats"].tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 2))
        XCTAssertLessThan(Date().timeIntervalSince(switched), 2)
        app.buttons["nav-settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))
        app.buttons["nav-play"].tap()
        XCTAssertTrue(app.staticTexts["White to move"].waitForExistence(timeout: aiReply), "the reply arrived while we were away or arrives now")
        XCTAssertTrue(square(app, "d4, white pawn").exists, "the play screen kept its game")
    }

    @MainActor
    func testPromotionInAGameOffersThePicker() {
        // The debug scenario sets up a pass-and-play game with a white pawn on g7 and pushes it.
        let app = launch(arguments: ["--scenario", "play-promotion"])
        XCTAssertTrue(app.staticTexts["Promote to"].waitForExistence(timeout: 10))
        app.buttons["queen"].tap()
        XCTAssertTrue(square(app, "g8, white queen").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Promote to"].exists)
        XCTAssertTrue(app.staticTexts["Check · Black to move"].exists)
        expectMove(app, "g8=Q+")
    }
}
