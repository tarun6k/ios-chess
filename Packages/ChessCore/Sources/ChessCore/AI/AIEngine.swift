// Ported 1:1 from src/ai/worker.ts and src/app/aiClient.ts — the AI worker as a Swift actor.
//
// TypeScript name → Swift name
//   const search = new Search()      → AIEngine.search (one engine owns one Search, so the transposition
//                                       table and history heuristic persist across requests like the worker's)
//   requestAiMove / requestHint /
//   requestAnalysis (aiClient.ts)    → move(_:) / hint(_:) / analyze(_:) — async, run on the actor (never on
//                                       the main thread), and honour Task cancellation
//   handleMove / handleHint /
//   handleAnalyze (worker.ts)        → same names (synchronous, actor-isolated); `ErrorResponse` → thrown
//                                       AIEngineError / FENError
//   judge(cpLoss, isBest)            → AIEngine.judge(cpLoss:isBest:)
//   uciToMove(pos, uci)              → AIEngine.uciToMove(_:_:)
//   Math.random (via chooseMove)     → the injected `random` closure
//
// Cancellation: the search polls `isCancelled` where it polls its deadline (every 2048 nodes) and
// abandons the running iteration; a cancelled request then throws `CancellationError` instead of
// returning the partial result. The public methods poll `Task.isCancelled`, so cancelling the awaiting
// Task is enough (Phase 6's controller does that where controller.ts discards stale replies via `moveSeq`).

public actor AIEngine {
    private var search = Search()
    private let random: @Sendable () -> Double

    /// - Parameter random: uniform [0, 1) source used by `chooseMove` (TS `Math.random`).
    public init(random: @escaping @Sendable () -> Double = systemUnitRandom) {
        self.random = random
    }

    /// TS `uciToMove`: the legal move written as `uci`, if any.
    public static func uciToMove(_ pos: Position, _ uci: String) -> Move? {
        pos.generateLegalMoves().first { $0.uci == uci }
    }

    /// TS `judge`: thresholds 50 / 120 / 250 cp.
    public static func judge(cpLoss: Int, isBest: Bool) -> Judgment {
        if isBest { return .best }
        if cpLoss >= 250 { return .blunder }
        if cpLoss >= 120 { return .mistake }
        if cpLoss >= 50 { return .inaccuracy }
        return .good
    }

    // MARK: - aiClient.ts

    /// TS `requestAiMove`.
    public func move(_ req: MoveRequest) async throws -> MoveResponse {
        try handleMove(req, isCancelled: { Task.isCancelled })
    }

    /// TS `requestHint`.
    public func hint(_ req: HintRequest) async throws -> HintResponse {
        try handleHint(req, isCancelled: { Task.isCancelled })
    }

    /// TS `requestAnalysis`.
    public func analyze(_ req: AnalyzeRequest) async throws -> AnalyzeResponse {
        try handleAnalyze(req, isCancelled: { Task.isCancelled })
    }

    // MARK: - worker.ts

    func handleMove(_ req: MoveRequest, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> MoveResponse {
        let pos = try Position(fen: req.fen)

        if let bookMove = req.bookMove, AIEngine.uciToMove(pos, bookMove) != nil {
            return MoveResponse(uci: bookMove, score: 0, depth: 0, nodes: 0, choiceIndex: 0, bestUci: bookMove)
        }

        let persona = personaForSkill(req.skill, moveTimeMs: req.moveTimeMs)
        let result = search.search(pos, options: SearchOptions(
            maxDepth: persona.maxDepth,
            moveTimeMs: persona.moveTimeMs,
            params: req.params ?? .neutral,
            historyKeys: req.historyKeys,
            isCancelled: isCancelled
        ))
        if isCancelled() { throw CancellationError() }
        guard result.best != nil else { throw AIEngineError.noLegalMoves }
        let idx = chooseMove(result.rootMoves, persona: persona, rng: random)
        let chosen = result.rootMoves[idx]
        return MoveResponse(
            uci: chosen.move.uci,
            score: chosen.score,
            depth: result.depth,
            nodes: result.nodes,
            choiceIndex: idx,
            bestUci: result.rootMoves[0].move.uci
        )
    }

    func handleHint(_ req: HintRequest, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> HintResponse {
        let pos = try Position(fen: req.fen)
        let result = search.search(pos, options: SearchOptions(
            maxDepth: 5, moveTimeMs: 1500, params: .neutral, historyKeys: req.historyKeys, isCancelled: isCancelled
        ))
        if isCancelled() { throw CancellationError() }
        guard let best = result.best else { throw AIEngineError.noLegalMoves }
        return HintResponse(uci: best.uci, score: result.score)
    }

    func handleAnalyze(_ req: AnalyzeRequest, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> AnalyzeResponse {
        var pos = try Position(fen: req.startFEN)
        var out: [AnalyzedMove] = []
        var keys: [String] = [pos.hashKey]
        for uci in req.uciMoves {
            guard let m = AIEngine.uciToMove(pos, uci) else { throw AIEngineError.illegalMoveInLine(uci) }
            let white = pos.turn == .white
            let before = search.search(pos, options: SearchOptions(
                maxDepth: 4, moveTimeMs: req.perMoveMs, historyKeys: keys, isCancelled: isCancelled
            ))
            if isCancelled() { throw CancellationError() }
            let bestScoreMover = before.rootMoves.isEmpty ? 0 : before.rootMoves[0].score
            let played = before.rootMoves.first { $0.move == m }
            // If the played move fell outside exact-window scoring, re-search it quickly.
            let playedScore = played?.score ?? (bestScoreMover - 400)
            let cpLoss = max(0, bestScoreMover - playedScore)
            let bestUci = before.rootMoves.isEmpty ? uci : before.rootMoves[0].move.uci

            pos.makeMove(m)
            keys.append(pos.hashKey)
            out.append(AnalyzedMove(
                uci: uci,
                evalAfter: white ? playedScore : -playedScore,
                evalBefore: white ? bestScoreMover : -bestScoreMover,
                bestUci: bestUci,
                judgment: AIEngine.judge(cpLoss: cpLoss, isBest: bestUci == uci),
                cpLoss: cpLoss
            ))
        }
        return AnalyzeResponse(moves: out)
    }
}
