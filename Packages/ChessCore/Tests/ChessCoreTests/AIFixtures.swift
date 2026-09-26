import Foundation
import Testing
@testable import ChessCore

// Expected values generated from the TypeScript by `.porting/tools/ai-dump.ts`
// (run `node_modules/.bin/vite-node .porting/tools/ai-dump.ts` from the repo root).

struct AIFixtures: Decodable, Sendable {
    struct Tables: Decodable, Sendable {
        var pieceValue: [Int]
        var pst: [String: [Int]]
        var passedBonus: [Int]
        var knightMovesD: [Int]
        var knightMovesF: [Int]
        var neutralParams: EvalParams
    }

    struct EvalCase: Decodable, Sendable, CustomTestStringConvertible {
        var fen: String
        var params: String
        var score: Int
        var testDescription: String { "\(fen) [\(params)]" }
    }

    struct RootMoveCase: Decodable, Sendable, Equatable {
        var uci: String
        var score: Int
    }

    struct SearchResultCase: Decodable, Sendable {
        var best: String?
        var score: Int
        var depth: Int
        var nodes: Int
        var rootMoves: [RootMoveCase]
        var pv: [String]
    }

    struct SearchCase: Decodable, Sendable, CustomTestStringConvertible {
        var fen: String
        var maxDepth: Int
        var params: String
        var historyKeys: [String]
        var result: SearchResultCase
        var testDescription: String { "\(fen) depth \(maxDepth) [\(params)]" }
    }

    struct TerminalCase: Decodable, Sendable {
        var fen: String
        var result: SearchResultCase
    }

    struct PersonaCase: Decodable, Sendable {
        var skill: Double
        var persona: Persona
        var elo: Int
    }

    struct EloCase: Decodable, Sendable {
        var elo: Int
        var skill: Double
    }

    struct ChooseMoveCase: Decodable, Sendable, CustomTestStringConvertible {
        var scores: [Int]
        var skill: Double
        var seed: Int
        var n: Int
        var picks: [Int]
        var testDescription: String { "skill \(skill) seed \(seed) scores \(scores)" }
    }

    struct RNG: Decodable, Sendable {
        var lcgSeed42: [Double]
        var lcgSeed7: [Double]
        var gaussianSeed42: [Double]
        var chooseMove: [ChooseMoveCase]
    }

    struct IdentifyCase: Decodable, Sendable {
        var sans: [String]
        var result: OpeningMatch?
    }

    struct ContinuationCase: Decodable, Sendable {
        var sans: [String]
        var preferTags: [OpeningTag]?
        var result: [String]
    }

    struct AnalyzeCase: Decodable, Sendable, CustomTestStringConvertible {
        var startFen: String
        var uciMoves: [String]
        var moves: [AnalyzedMove]
        var testDescription: String { uciMoves.joined(separator: " ") }
    }

    struct PuzzleCase: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var kind: String
        var fen: String
        var solution: String
        var best: String
        var bestScore: Int
        var solutionScore: Int?
        var depth: Int
        var nodes: Int
        var testDescription: String { "\(id) (\(kind))" }
    }

    var mate: Int
    var tables: Tables
    var paramSets: [String: EvalParams]
    var evals: [EvalCase]
    var searches: [SearchCase]
    var terminal: [TerminalCase]
    var personas: [PersonaCase]
    var eloToSkill: [EloCase]
    var rng: RNG
    var book: [OpeningLine]
    var identify: [IdentifyCase]
    var continuations: [ContinuationCase]
    var analyze: [AnalyzeCase]
    var puzzles: [PuzzleCase]

    /// Decoded once; parameterized tests read their arguments from here.
    static let shared: AIFixtures = {
        guard let url = Bundle.module.url(forResource: "ai-fixtures", withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("Fixtures/ai-fixtures.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(AIFixtures.self, from: Data(contentsOf: url))
        } catch {
            fatalError("ai-fixtures.json does not decode: \(error)")
        }
    }()

    /// The EvalParams a fixture case refers to by name.
    func params(_ name: String) throws -> EvalParams {
        try #require(paramSets[name], "unknown param set \(name)")
    }
}

/// The `moveTimeMs` the generator used so every fixture search ran to its full depth.
let unlimitedMoveTime: Double = 600_000

/// The seeded LCG from tests/ai.test.ts:
/// `seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff`.
/// JS multiplies in doubles (the product exceeds 2^53 and is rounded) before `&` truncates to 32 bits.
struct TestLCG {
    var seed: Int

    init(seed: Int) { self.seed = seed }

    mutating func next() -> Double {
        let product = Double(seed) * 1103515245.0 + 12345.0
        seed = Int(UInt64(product) & 0x7fff_ffff)
        return Double(seed) / Double(0x7fff_ffff)
    }
}

extension SearchResult {
    /// The fixture's view of a result (moves as UCI strings).
    var ucis: (best: String?, rootMoves: [AIFixtures.RootMoveCase], pv: [String]) {
        (best?.uci, rootMoves.map { AIFixtures.RootMoveCase(uci: $0.move.uci, score: $0.score) }, pv.map(\.uci))
    }
}
