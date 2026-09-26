import XCTest

/// Layout checks for every device family and orientation: nothing spills past the window's sides,
/// every anchor is on screen or can be scrolled onto it, the board keeps its aspect and the nav bar
/// stays tappable. The iPhone is portrait-only (Info.plist), so the landscape run needs an iPad
/// simulator. Set `TEST_RUNNER_ADAPTIVE_CHESS_SHOTS=<dir>` to keep a PNG of every state for a
/// visual review.
final class LayoutUITests: XCTestCase {
    private struct Scene {
        let scenario: String
        /// Elements that must be inside the window, directly or after scrolling the page.
        let anchors: [(XCUIApplication) -> XCUIElement]
        /// A dialog backdrop covers the whole viewport, nav included (TS `position: fixed; inset: 0`).
        var modal = false
    }

    // Page titles are looked up inside the scroll view: the nav bar sits beside it and its buttons
    // carry the same labels ("Insights", "Settings").
    @MainActor
    private static let scenes: [Scene] = [
        Scene(scenario: "home", anchors: [{ $0.buttons["home-start"] }, { $0.staticTexts["An opponent that learns you"] }]),
        Scene(scenario: "play-start", anchors: [
            { $0.descendants(matching: .any).matching(NSPredicate(format: "label == 'e4'")).firstMatch },
            { $0.descendants(matching: .any).matching(NSPredicate(format: "label == 'a1, white rook'")).firstMatch },
            { $0.descendants(matching: .any).matching(NSPredicate(format: "label == 'h8, black rook'")).firstMatch },
            { $0.buttons["play-new-game"] },
        ]),
        Scene(scenario: "puzzles", anchors: [{ $0.scrollViews.staticTexts["Challenges"] }, { $0.buttons["puzzle-m1-backrank"].firstMatch }]),
        Scene(scenario: "insights", anchors: [{ $0.scrollViews.staticTexts["Insights"] }]),
        Scene(scenario: "settings", anchors: [{ $0.scrollViews.staticTexts["Settings"] }, { $0.buttons.matching(identifier: "setting-Coordinates").firstMatch }]),
        Scene(scenario: "gameover-pvp", anchors: [{ $0.staticTexts["White wins"] }, { $0.buttons["play-game-over-new"] }, { $0.buttons["play-export-pgn"] }], modal: true),
    ]

    @MainActor
    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The simulator's name ("iPad mini (A17 Pro)", without xcodebuild's "Clone 1 of " prefix)
    /// as a file-name stem, so the shots of two iPads do not overwrite each other; `UIDevice.model`
    /// is "iPad" for both. Falls back to the model and the window's portrait size.
    @MainActor
    private static func deviceName(for app: XCUIApplication) -> String {
        var name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if let clone = name.range(of: #"^Clone \d+ of "#, options: .regularExpression) {
            name.removeSubrange(clone)
        }
        if name.isEmpty {
            let size = app.windows.firstMatch.frame.size
            name = "\(UIDevice.current.model) \(Int(min(size.width, size.height)))x\(Int(max(size.width, size.height)))"
        }
        return name.replacingOccurrences(of: "[()]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testPortraitLayouts() {
        check(.portrait)
    }

    @MainActor
    func testLandscapeLayouts() throws {
        try XCTSkipUnless(Self.isPad, "the iPhone is portrait-only; run this on an iPad simulator")
        check(.landscapeLeft)
    }

    /// `UISupportedInterfaceOrientations` locks the iPhone to portrait: the window must ignore a
    /// device rotation instead of showing a layout that was never designed for it.
    @MainActor
    func testPhoneIgnoresRotation() throws {
        try XCTSkipIf(Self.isPad, "the iPad rotates; see testLandscapeLayouts")
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--scenario", "home"]
        app.launch()
        XCTAssertTrue(app.buttons["home-start"].waitForExistence(timeout: 10))
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            _ = app.staticTexts["never-there"].waitForExistence(timeout: 1.5)
            let window = app.windows.firstMatch.frame
            XCTAssertLessThan(window.width, window.height, "the window rotated to \(orientation.rawValue) on a portrait-only phone")
            XCTAssertTrue(app.buttons["home-start"].isHittable, "the home screen is not tappable after rotating to \(orientation.rawValue)")
        }
    }

    @MainActor
    private func check(_ orientation: UIDeviceOrientation) {
        for scene in Self.scenes {
            let app = XCUIApplication()
            app.launchArguments = ["--reset-state", "--scenario", scene.scenario]
            app.launch()
            XCUIDevice.shared.orientation = orientation
            let anchors = scene.anchors.map { $0(app) }
            for anchor in anchors {
                XCTAssertTrue(anchor.waitForExistence(timeout: 10), "\(scene.scenario): \(anchor) missing")
            }
            // Let the rotation and the scenario's own waits finish.
            _ = app.staticTexts["never-there"].waitForExistence(timeout: 1.5)

            let window = app.windows.firstMatch.frame
            let landscape = orientation.isLandscape
            XCTAssertEqual(window.width > window.height, landscape, "\(scene.scenario): the window did not rotate")
            let name = "\(scene.scenario)-\(orientation.name)"
            snapshot(app, name)

            for route in ["home", "play", "puzzles", "stats", "settings"] {
                XCTAssertEqual(app.buttons["nav-\(route)"].isHittable, !scene.modal,
                               "\(name): nav-\(route) \(scene.modal ? "tappable through the dialog backdrop" : "not tappable")")
            }
            var scrolled = false
            for anchor in anchors {
                let frame = anchor.frame
                XCTAssertTrue(frame.minX >= window.minX - 0.5 && frame.maxX <= window.maxX + 0.5,
                              "\(name): \(anchor.label) at \(frame) spills past the window's sides \(window)")
                // The page is one column on narrow screens (the side panel wraps under the board,
                // the puzzle list runs on), so an anchor below the fold is fine as long as the page
                // scrolls to it.
                if !window.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                    scrolled = scrollIntoView(anchor, in: app, window: window)
                    XCTAssertTrue(window.insetBy(dx: -0.5, dy: -0.5).contains(anchor.frame),
                                  "\(name): \(anchor.label) at \(anchor.frame) cannot be scrolled into the window \(window)")
                }
            }
            if scene.scenario == "play-start" {
                let a1 = anchors[1].frame, h8 = anchors[2].frame
                let side = h8.maxX - a1.minX
                XCTAssertEqual(side, a1.maxY - h8.minY, accuracy: 1.5, "\(name): the board is not square")
                XCTAssertEqual(a1.width * 8, side, accuracy: 2, "\(name): squares do not tile the board")
                XCTAssertGreaterThanOrEqual(a1.width, 40, "\(name): squares too small to tap")
                XCTAssertLessThanOrEqual(a1.width, 62.5, "\(name): squares exceed the 62px cap")
                XCTAssertTrue(anchors[3].isHittable, "\(name): the side panel's New game button cannot be reached")
            }
            if scrolled { snapshot(app, "\(name)-scrolled") }
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Scrolls the page with drags in `element`'s own column, starting low in the window: an
    /// anchor below the fold sits in the page column or the side panel, never on the board,
    /// whose drags lift pieces (on a short window the board reaches lower than the drag's start).
    /// Returns true once `element` is inside `window`.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, window: CGRect) -> Bool {
        let x = min(max(element.frame.midX, window.minX + 20), window.maxX - 20) / window.width
        for _ in 0..<8 {
            if window.insetBy(dx: -0.5, dy: -0.5).contains(element.frame) { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.8))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to)
            _ = app.staticTexts["never-there"].waitForExistence(timeout: 0.5)
        }
        return window.insetBy(dx: -0.5, dy: -0.5).contains(element.frame)
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["ADAPTIVE_CHESS_SHOTS"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(Self.deviceName(for: app))-\(name).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("could not write \(url.path): \(error)")
        }
    }
}

private extension UIDeviceOrientation {
    var name: String { isLandscape ? "landscape" : "portrait" }
}
