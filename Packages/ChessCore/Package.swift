// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
        .library(name: "ChessServices", targets: ["ChessServices"]),
    ],
    targets: [
        // Rules engine (Engine/) and adaptive AI (AI/), ported 1:1 from src/engine and src/ai.
        .target(name: "ChessCore"),
        // Clock, puzzles, progression, storage, store and controller, ported from src/app.
        .target(name: "ChessServices", dependencies: ["ChessCore"]),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
        .testTarget(name: "ChessServicesTests", dependencies: ["ChessServices"]),
    ],
    swiftLanguageModes: [.v6]
)
