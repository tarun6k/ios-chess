// Ported from src/ai/protocol.ts: the messages between the app and the AI worker.
//
// The TS envelopes carry `id` and `type` so aiClient.ts can match a worker reply to its promise; the
// Swift engine is an actor called directly (`await engine.move(…)`), so only the payload fields are kept
// and `ErrorResponse` becomes the thrown `AIEngineError`. `Judgment` and `AnalyzedMove` live in
// AnalyzedMove.swift (Phase 2, persisted by the archive).

public struct MoveRequest: Hashable, Sendable {
    public var fen: String
    public var historyKeys: [String]
    public var skill: Double
    public var moveTimeMs: Double
    public var params: EvalParams?
    /// UCI move to force (opening book / prepared line), skipping search.
    public var bookMove: String?

    public init(fen: String, historyKeys: [String], skill: Double, moveTimeMs: Double,
                params: EvalParams? = nil, bookMove: String? = nil) {
        self.fen = fen
        self.historyKeys = historyKeys
        self.skill = skill
        self.moveTimeMs = moveTimeMs
        self.params = params
        self.bookMove = bookMove
    }
}

public struct HintRequest: Hashable, Sendable {
    public var fen: String
    public var historyKeys: [String]

    public init(fen: String, historyKeys: [String]) {
        self.fen = fen
        self.historyKeys = historyKeys
    }
}

public struct AnalyzeRequest: Hashable, Sendable {
    /// TS `startFen`.
    public var startFEN: String
    public var uciMoves: [String]
    /// ms budget per position
    public var perMoveMs: Double

    /// The default budget is aiClient.ts `requestAnalysis(startFen, uciMoves, perMoveMs = 350)`.
    public init(startFEN: String, uciMoves: [String], perMoveMs: Double = 350) {
        self.startFEN = startFEN
        self.uciMoves = uciMoves
        self.perMoveMs = perMoveMs
    }
}

public struct MoveResponse: Hashable, Sendable {
    public var uci: String
    /// cp from the mover's POV
    public var score: Int
    public var depth: Int
    public var nodes: Int
    /// index chosen among root candidates (0 = engine best) — for the adaptation summary
    public var choiceIndex: Int
    public var bestUci: String

    public init(uci: String, score: Int, depth: Int, nodes: Int, choiceIndex: Int, bestUci: String) {
        self.uci = uci
        self.score = score
        self.depth = depth
        self.nodes = nodes
        self.choiceIndex = choiceIndex
        self.bestUci = bestUci
    }
}

public struct HintResponse: Hashable, Sendable {
    public var uci: String
    public var score: Int

    public init(uci: String, score: Int) {
        self.uci = uci
        self.score = score
    }
}

public struct AnalyzeResponse: Hashable, Sendable {
    public var moves: [AnalyzedMove]

    public init(moves: [AnalyzedMove]) {
        self.moves = moves
    }
}

/// TS `ErrorResponse.message` texts produced by worker.ts.
public enum AIEngineError: Error, Hashable, Sendable, CustomStringConvertible {
    case noLegalMoves
    case illegalMoveInLine(String)

    public var description: String {
        switch self {
        case .noLegalMoves: return "no legal moves"
        case .illegalMoveInLine(let uci): return "illegal move in line: " + uci
        }
    }
}
