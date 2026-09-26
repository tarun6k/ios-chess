import Foundation
import Testing
@testable import ChessCore

// Expected values generated from the TypeScript by `.porting/tools/adaptation-dump.ts`
// (run `node_modules/.bin/vite-node .porting/tools/adaptation-dump.ts` from the repo root).

struct AdaptationFixtures: Decodable, Sendable {
    /// `extractFacts` output as the generator serialised it.
    struct Facts: Decodable, Sendable, Equatable {
        var playerColor: PieceColor
        var captureRate: Double
        var earlyQueenPly: Int
        var castlePly: Int
        var checks: Int
        var pawnStorm: Int
        var tradeRate: Double
        var avgThinkMs: Double
        var openingName: String?

        init(_ f: GameFacts) {
            playerColor = f.playerColor
            captureRate = f.captureRate
            earlyQueenPly = f.earlyQueenPly
            castlePly = f.castlePly
            checks = f.checks
            pawnStorm = f.pawnStorm
            tradeRate = f.tradeRate
            avgThinkMs = f.avgThinkMs
            openingName = f.openingName
        }
    }

    /// Per-colour values (`{ w, b }`).
    struct Sides<T: Decodable & Sendable>: Decodable, Sendable {
        var w: T
        var b: T

        subscript(color: PieceColor) -> T { color == .white ? w : b }
    }

    struct ResultCase: Decodable, Sendable {
        var score: String
        var kind: String
        var winner: PieceColor?
        var message: String
    }

    struct Synthetic: Decodable, Sendable {
        var analysis: [AnalyzedMove]
        var weaknesses: Sides<[String: Int]>
    }

    struct GameCase: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var startFen: String
        var sans: [String]
        /// `thinkMs` meta per ply (`null` = no meta)
        var thinkMs: [Int?]
        /// "resign:w" | "resign:b" | null
        var end: String?
        var result: ResultCase?
        var facts: Sides<Facts>
        /// worker.ts analysis at depth 4 with an unlimited budget
        var analysis: [AnalyzedMove]
        var weaknesses: Sides<[String: Int]>
        /// hand-crafted analysis that trips every weakness rule
        var synthetic: Synthetic
        var testDescription: String { id }
    }

    struct BookGameCase: Decodable, Sendable {
        var id: String
        var startFen: String
        var sans: [String]
        var end: String?
    }

    struct ClassifyCase: Decodable, Sendable, CustomTestStringConvertible {
        var name: String
        var features: StyleFeatures
        var label: StyleLabel
        var scores: [String: Int]
        var testDescription: String { name }
    }

    struct RatingStep: Decodable, Sendable, CustomTestStringConvertible {
        var rating: Int
        var games: Int
        var aiElo: Int
        var score: Double
        var result: Int
        var history: [RatingPoint]
        var testDescription: String { "\(rating) after \(games) games vs \(aiElo) scoring \(score)" }
    }

    struct RatingCap: Decodable, Sendable {
        var calls: Int
        var model: PlayerModel
    }

    struct Rating: Decodable, Sendable {
        var steps: [RatingStep]
        var cap: RatingCap
    }

    struct TargetEloCase: Decodable, Sendable, CustomTestStringConvertible {
        var rating: Int
        var streak: Int
        var mode: DifficultyMode
        var result: Int
        var testDescription: String { "\(rating) streak \(streak) \(mode)" }
    }

    struct EloCase: Decodable, Sendable, CustomTestStringConvertible {
        var elo: Int
        var skill: Double
        var testDescription: String { "\(elo)" }
    }

    struct PlanJSON: Decodable, Sendable {
        var skill: Double
        var aiElo: Int
        var params: EvalParams
        var bookTags: [OpeningTag]
        var mirrorOpening: String?
        var notes: [String]
        var styleLabel: StyleLabel

        var plan: AdaptationPlan {
            AdaptationPlan(skill: skill, aiElo: aiElo, params: params, bookTags: bookTags, mirrorOpening: mirrorOpening,
                           notes: notes, styleLabel: styleLabel)
        }
    }

    struct PlanCase: Decodable, Sendable, CustomTestStringConvertible {
        var name: String
        var model: PlayerModel
        var mode: DifficultyMode
        var aiColor: PieceColor
        /// scripted `Math.random` values, in order
        var rng: [Double]
        /// how many of them planForGame consumed
        var consumed: Int
        var plan: PlanJSON
        var testDescription: String { name }
    }

    struct PickBookCase: Decodable, Sendable, CustomTestStringConvertible {
        var sans: [String]
        var bookTags: [OpeningTag]
        var rng: [Double]
        var consumed: Int
        var result: String?
        var testDescription: String { "\(sans.joined(separator: " ")) [\(bookTags.map(\.rawValue).joined(separator: ","))] rng \(rng)" }
    }

    struct WeaknessEntry: Decodable, Sendable {
        var key: WeaknessKey
        var count: Int
    }

    struct TopWeaknessesCase: Decodable, Sendable {
        var weaknesses: WeaknessCounts
        /// nil = the default argument
        var n: Int?
        var result: [WeaknessEntry]
    }

    struct Step: Decodable, Sendable {
        var game: String
        var playerColor: PieceColor
        /// "real" | "synthetic" | null
        var analysis: String?
        var vsAi: Bool
        var aiElo: Int?
        var now: Int
    }

    struct ReplayStep: Decodable, Sendable {
        var step: Step
        var facts: Facts
        /// `JSON.stringify(model)` after the step
        var json: String
    }

    struct Replay: Decodable, Sendable {
        var steps: [ReplayStep]
        var storedWithoutAdaptation: String
        var storedWithAdaptation: String
        var fresh: String
    }

    var now: Int
    var games: [GameCase]
    var bookGames: [BookGameCase]
    var classify: [ClassifyCase]
    var rating: Rating
    var targetElo: [TargetEloCase]
    var eloToSkill: [EloCase]
    var plans: [PlanCase]
    var pickBook: [PickBookCase]
    var topWeaknesses: [TopWeaknessesCase]
    var replay: Replay

    /// Decoded once; parameterized tests read their arguments from here.
    static let shared: AdaptationFixtures = {
        guard let url = Bundle.module.url(forResource: "adaptation-fixtures", withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("Fixtures/adaptation-fixtures.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(AdaptationFixtures.self, from: Data(contentsOf: url))
        } catch {
            fatalError("adaptation-fixtures.json does not decode: \(error)")
        }
    }()

    /// The generator's `thinkFor(ply)`: no meta on every fifth ply, `thinkMs: 0` on the next, else a growing value.
    static func thinkFor(_ ply: Int) -> Int? {
        ply % 5 == 0 ? nil : ply % 5 == 1 ? 0 : 400 + 137 * ply
    }

    /// The generator's `buildGame`.
    static func buildGame(startFen: String, sans: [String], thinkMs: [Int?]?, end: String?,
                          sourceLocation: SourceLocation = #_sourceLocation) throws -> Game {
        var game = try Game(fen: startFen)
        for (ply, san) in sans.enumerated() {
            let t: Int? = thinkMs.map { $0[ply] } ?? thinkFor(ply)
            try #require(game.playSAN(san, thinkMs: t) != nil, "illegal SAN \(san) at ply \(ply)", sourceLocation: sourceLocation)
        }
        switch end {
        case "resign:w": game.resign(.white)
        case "resign:b": game.resign(.black)
        default: break
        }
        return game
    }

    func build(_ c: GameCase, sourceLocation: SourceLocation = #_sourceLocation) throws -> Game {
        try Self.buildGame(startFen: c.startFen, sans: c.sans, thinkMs: c.thinkMs, end: c.end, sourceLocation: sourceLocation)
    }

    func build(_ c: BookGameCase, sourceLocation: SourceLocation = #_sourceLocation) throws -> Game {
        try Self.buildGame(startFen: c.startFen, sans: c.sans, thinkMs: nil, end: c.end, sourceLocation: sourceLocation)
    }

    func game(_ id: String) -> GameCase? {
        games.first { $0.id == id }
    }

    /// Every replay game by id.
    func builtGames(sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Game] {
        var out: [String: Game] = [:]
        for c in games { out[c.id] = try build(c, sourceLocation: sourceLocation) }
        for c in bookGames { out[c.id] = try build(c, sourceLocation: sourceLocation) }
        return out
    }
}

/// The TS `Partial<Record<WeaknessKey, number>>` of a fixture as the Swift result type.
func weaknessMap(_ raw: [String: Int], sourceLocation: SourceLocation = #_sourceLocation) throws -> [WeaknessKey: Int] {
    var out: [WeaknessKey: Int] = [:]
    for (k, v) in raw {
        out[try #require(WeaknessKey(rawValue: k), "unknown weakness \(k)", sourceLocation: sourceLocation)] = v
    }
    return out
}

/// The generator's scripted `Math.random`: hands out the listed values in order and counts the calls.
final class ScriptedRNG {
    private let values: [Double]
    private(set) var consumed = 0
    /// calls made after the script ran out (the TS threw here)
    private(set) var exhaustedCalls = 0

    init(_ values: [Double]) { self.values = values }

    func next() -> Double {
        guard consumed < values.count else {
            exhaustedCalls += 1
            return 0
        }
        defer { consumed += 1 }
        return values[consumed]
    }
}
