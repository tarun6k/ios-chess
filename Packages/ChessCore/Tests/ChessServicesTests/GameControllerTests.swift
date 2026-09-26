import Foundation
import os
import Testing
import ChessCore
@testable import ChessServices

// tests/controller.test.ts. The TS mocks the worker client (`requestAiMove` / `requestHint` /
// `requestAnalysis` default to never-resolving promises), the sound / haptic objects (no-ops) and runs
// on fake timers frozen at 2026-06-01T09:00:00Z. Here: `ScriptedAI` (queued replies, otherwise parked
// on a continuation), `RecordingFeedback` and a `ManualTimeSource` started at that instant.
//
// The TS issues its requests synchronously; the Swift controller issues them from tasks, so the tests
// `drain()` — yield until every started request has either finished or parked — before asserting on
// the requests seen by the AI. `settle()` is the TS `advanceTimersByTimeAsync(500)`: drain, let the
// 450 ms humanlike pause elapse, drain again.

enum TestFailure: Error {
    case workerDied
    case boom
}

func moveRes(_ uci: String) -> MoveResponse {
    MoveResponse(uci: uci, score: 0, depth: 1, nodes: 1, choiceIndex: 0, bestUci: uci)
}

func hintRes(_ uci: String, _ score: Int) -> HintResponse {
    HintResponse(uci: uci, score: score)
}

func analysed(_ uci: String, _ bestUci: String, _ cpLoss: Int) -> AnalyzedMove {
    AnalyzedMove(uci: uci, evalAfter: -cpLoss, evalBefore: 0, bestUci: bestUci,
                 judgment: cpLoss >= 200 ? .blunder : cpLoss > 0 ? .inaccuracy : .best, cpLoss: cpLoss)
}

/// The `resolveFirst` handle of the stale-reply test: a move request kept open until `resolve` is called.
/// It deliberately ignores cancellation, standing in for an engine that finishes its search anyway.
@MainActor
final class HeldRequest {
    fileprivate var resume: (@Sendable (Result<MoveResponse, any Error>) -> Void)? = nil

    func resolve(_ response: MoveResponse) {
        resume?(.success(response))
        resume = nil
    }
}

/// The mocked worker client: scripted replies in order; once exhausted (or with nothing scripted) a
/// request parks forever like `pending<T>()`, unless its task is cancelled.
@MainActor
final class ScriptedAI: AIService {
    private(set) var moveRequests: [MoveRequest] = []
    private(set) var hintRequests: [HintRequest] = []
    private(set) var analyzeRequests: [AnalyzeRequest] = []
    private var moveQueue: [MoveResponse] = []
    private var hintQueue: [HintResponse] = []
    private var analyzeQueue: [Result<AnalyzeResponse, any Error>] = []
    private var heldMove: HeldRequest? = nil
    /// `mockRejectedValue(new Error('worker died'))`
    var failMoves = false
    private var nextId = 0
    /// Parked requests by id → "fail with this error" (nonisolated so a cancellation handler can reach it).
    private let parked = OSAllocatedUnfairLock<[Int: @Sendable (any Error) -> Void]>(initialState: [:])

    /// Requests currently parked on the never-resolving default.
    nonisolated var hangingCount: Int { parked.withLock { $0.count } }

    /// TS `scriptAi(...ucis)`.
    func script(_ ucis: String...) { moveQueue = ucis.map(moveRes) }
    /// TS `requestHint.mockResolvedValueOnce(hintRes(uci, score))`.
    func scriptHint(_ uci: String, _ score: Int) { hintQueue.append(hintRes(uci, score)) }
    func scriptAnalysis(_ moves: [AnalyzedMove]) { analyzeQueue.append(.success(AnalyzeResponse(moves: moves))) }
    func failNextAnalysis() { analyzeQueue.append(.failure(TestFailure.boom)) }

    func holdNextMove() -> HeldRequest {
        let held = HeldRequest()
        heldMove = held
        return held
    }

    func move(_ request: MoveRequest) async throws -> MoveResponse {
        moveRequests.append(request)
        if failMoves { throw TestFailure.workerDied }
        if let held = heldMove {
            heldMove = nil
            return try await park(cancellable: false) { resume in held.resume = resume }
        }
        if !moveQueue.isEmpty { return moveQueue.removeFirst() }
        return try await park(cancellable: true)
    }

    func hint(_ request: HintRequest) async throws -> HintResponse {
        hintRequests.append(request)
        if !hintQueue.isEmpty { return hintQueue.removeFirst() }
        return try await park(cancellable: true)
    }

    func analyze(_ request: AnalyzeRequest) async throws -> AnalyzeResponse {
        analyzeRequests.append(request)
        if !analyzeQueue.isEmpty { return try analyzeQueue.removeFirst().get() }
        return try await park(cancellable: true)
    }

    private func park<T: Sendable>(
        cancellable: Bool,
        _ attach: (@escaping @Sendable (Result<T, any Error>) -> Void) -> Void = { _ in }
    ) async throws -> T {
        let id = nextId
        nextId += 1
        let parked = self.parked
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                let resume: @Sendable (Result<T, any Error>) -> Void = { result in
                    // the first resumer wins; later ones find nothing to resume
                    if parked.withLock({ $0.removeValue(forKey: id) }) != nil {
                        continuation.resume(with: result)
                    }
                }
                parked.withLock { $0[id] = { error in resume(.failure(error)) } }
                attach(resume)
            }
        } onCancel: {
            if cancellable {
                let fail = parked.withLock { $0[id] }
                fail?(CancellationError())
            }
        }
    }
}

@MainActor
final class RecordingFeedback: FeedbackService {
    private(set) var sounds: [SoundEvent] = []
    private(set) var haptics: [HapticEvent] = []

    func play(_ sound: SoundEvent) { sounds.append(sound) }
    func trigger(_ haptic: HapticEvent) { haptics.append(haptic) }

    func reset() {
        sounds = []
        haptics = []
    }
}

/// The TS `beforeEach`: fresh state, mocks and fake clock.
@MainActor
final class Harness {
    /// `Date.parse('2026-06-01T09:00:00Z')`
    static let epoch = 1_780_304_400_000

    let state = AppState(storage: .inMemory())
    let ai = ScriptedAI()
    let feedback = RecordingFeedback()
    let time = ManualTimeSource(nowMs: Harness.epoch)
    private(set) var controllers: [GameController] = []

    init() {}

    /// `new GameController()` on the shared state and mocks.
    func controller() -> GameController {
        let c = GameController(state: state, ai: ai, feedback: feedback, timeSource: time)
        controllers.append(c)
        return c
    }

    /// Yields until every started request has either finished or parked on the never-resolving default.
    func drain() async {
        for _ in 0..<10_000 {
            let inflight = controllers.reduce(0) { $0 + $1.inflightRequests }
            if inflight <= ai.hangingCount { return }
            await Task.yield()
        }
        Issue.record("AI requests did not settle")
    }

    /// TS `settle`: let the AI's humanlike 450 ms pause elapse and promises settle.
    func settle() async {
        await drain()
        time.advance(ms: 500)
        await drain()
    }

    /// TS `play(c, uci)`.
    func play(_ c: GameController, _ uci: String) throws {
        let m = try #require(c.uciToMove(uci), "illegal in test: \(uci)")
        #expect(c.playMove(m))
    }

    /// `JSON.parse(JSON.stringify(state.saved))`.
    func savedRoundTrip() throws -> SavedGame {
        let saved = try #require(state.saved)
        return try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(saved))
    }
}

func puzzle(_ id: String) throws -> Puzzle {
    try #require(puzzles.first { $0.id == id }, "puzzle \(id) missing")
}

func constraint(_ kind: ConstraintKind) throws -> ConstraintGame {
    try #require(constraints.first { $0.kind == kind }, "constraint \(kind.rawValue) missing")
}

@MainActor
@Suite("GameController: game setup")
struct GameSetupTests {
    @Test("pass-and-play starts from the initial position with no clock, plan or AI")
    func passAndPlay() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        #expect(c.game.status == .active)
        #expect(c.game.startFEN == Position.startFEN)
        #expect(c.humanTurn)
        #expect(c.clock == nil)
        #expect(c.plan == nil)
        #expect(c.hintsLeft == 3)
        #expect(h.ai.moveRequests.isEmpty)
        #expect(h.state.saved?.mode == .pvp)
        #expect(h.state.saved?.uciMoves == [])
    }

    @Test("bumps gameId for every new game so the UI can reset local state")
    func gameId() throws {
        let h = Harness()
        let c = h.controller()
        let g0 = c.gameId
        try c.newGame(mode: .pvp)
        try c.newGame(mode: .pvp)
        #expect(c.gameId == g0 + 2)
    }

    @Test("vs AI builds an adaptation plan and takes its skill from the player model")
    func vsAiPlan() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        let plan = try #require(c.plan)
        #expect(c.aiSkill == plan.skill)
        #expect(c.aiElo == plan.aiElo)
        #expect(c.humanTurn)
        #expect(h.ai.moveRequests.isEmpty)
    }
}

@MainActor
@Suite("GameController: moves and turns")
struct MovesAndTurnsTests {
    @Test("records SAN and autosaves the UCI line after every ply")
    func recordsSan() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        try h.play(c, "e2e4")
        try h.play(c, "e7e5")
        #expect(c.game.sanLine() == ["e4", "e5"])
        #expect(h.state.saved?.uciMoves == ["e2e4", "e7e5"])
        #expect(h.state.saved?.thinkMs.count == 2)
    }

    @Test("rejects illegal moves and moves after the game has ended")
    func rejectsIllegal() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        #expect(c.uciToMove("e2e5") == nil)
        c.resign()
        #expect(c.playMove(c.game.position.generateLegalMoves()[0]) == false)
    }

    @Test("as Black, the AI moves first after a humanlike pause")
    func aiMovesFirst() async throws {
        let h = Harness()
        h.ai.script("e2e4")
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .black)
        #expect(c.thinking)
        #expect(!c.humanTurn)
        await h.drain()
        #expect(h.ai.moveRequests.count == 1)
        #expect(h.ai.moveRequests.first?.fen == Position.startFEN)
        h.time.advance(ms: 100)
        await h.drain()
        #expect(c.game.history.isEmpty) // still pacing
        await h.settle()
        #expect(!c.thinking)
        #expect(c.game.sanLine() == ["e4"])
        #expect(c.humanTurn)
    }

    @Test("answers the player's move")
    func answersMove() async throws {
        let h = Harness()
        h.ai.script("e7e5")
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "e2e4")
        #expect(c.thinking)
        #expect(!c.humanTurn)
        await h.settle()
        #expect(c.game.sanLine() == ["e4", "e5"])
        #expect(c.humanTurn)
        #expect(h.state.saved?.uciMoves == ["e2e4", "e7e5"])
    }

    @Test("ignores a stale AI reply that arrives after a new game started")
    func staleReply() async throws {
        let h = Harness()
        let held = h.ai.holdNextMove()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .black)
        await h.drain() // the first request is now waiting on `held`
        h.ai.script("d2d4")
        try c.newGame(mode: .ai, playerColor: .black)
        held.resolve(moveRes("e2e4"))
        await h.settle()
        #expect(c.game.sanLine() == ["d4"])
    }

    @Test("plays any legal move if the AI worker fails, so the game never stalls")
    func workerFails() async throws {
        let h = Harness()
        h.ai.failMoves = true
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .black)
        await h.settle()
        #expect(!c.thinking)
        #expect(c.game.history.count == 1)
        #expect(c.humanTurn)
    }
}

@MainActor
@Suite("GameController: takebacks")
struct TakebackTests {
    @Test("are allowed only in casual, untimed, non-challenge games with a move to undo")
    func allowedOnly() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        #expect(!c.takebacksAllowed)
        try h.play(c, "e2e4")
        #expect(c.takebacksAllowed)
        h.state.settings.takebacks = false
        #expect(!c.takebacksAllowed)
        h.state.settings.takebacks = true

        try c.newGame(mode: .pvp, timeControl: timePresets[2])
        try h.play(c, "e2e4")
        #expect(!c.takebacksAllowed)

        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: puzzles[0]))
        #expect(!c.takebacksAllowed)
    }

    @Test("vs AI, undo rewinds both plies back to the player's turn")
    func undoVsAi() async throws {
        let h = Harness()
        h.ai.script("e7e5")
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "e2e4")
        await h.settle()
        #expect(c.game.history.count == 2)
        c.undo()
        #expect(c.game.history.isEmpty)
        #expect(c.humanTurn)
        #expect(h.ai.moveRequests.count == 1)
        #expect(h.state.saved?.uciMoves == [])
    }

    @Test("in pass-and-play, undo rewinds one ply")
    func undoPvp() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        try h.play(c, "e2e4")
        try h.play(c, "e7e5")
        c.undo()
        #expect(c.game.sanLine() == ["e4"])
    }
}

@MainActor
@Suite("GameController: puzzles")
struct PuzzleTests {
    @Test("sets up the puzzle side to move with no hints and a full-strength defender")
    func setsUp() throws {
        let backRank = try puzzle("m1-backrank")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank))
        #expect(c.game.startFEN == backRank.fen)
        #expect(c.playerColor == .white)
        #expect(c.puzzleState == .solving)
        #expect(c.hintsLeft == 0)
        #expect(c.aiSkill == 20)
        #expect(c.isChallengeGame)
    }

    @Test("a mate-in-one is solved by mating; XP is granted once")
    func mateInOne() throws {
        let backRank = try puzzle("m1-backrank")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank))
        try h.play(c, "a1a8")
        #expect(c.puzzleState == .solved)
        #expect(c.game.result?.kind == .checkmate)
        #expect(h.state.progress.xp == backRank.xp)
        #expect(h.state.progress.solvedPuzzles == [backRank.id])
        #expect(h.state.progress.counters.puzzlesSolved == 1)
        #expect(h.state.saved == nil)
        // puzzles are not games
        #expect(h.state.progress.counters.gamesPlayed == 0)
        #expect(h.state.archive.isEmpty)

        c.retryPuzzle()
        #expect(c.puzzleState == .solving)
        try h.play(c, "a1a8")
        #expect(h.state.progress.xp == backRank.xp)
        #expect(h.state.progress.counters.puzzlesSolved == 2)
    }

    @Test("a non-mating move in a mate-in-one is wrong")
    func nonMating() throws {
        let backRank = try puzzle("m1-backrank")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank))
        try h.play(c, "a1a7")
        #expect(c.puzzleState == .wrong)
        #expect(h.state.progress.xp == 0)
    }

    @Test("a tactic only accepts the engine-best move")
    func tactic() throws {
        let fork = try puzzle("t-fork")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: fork))
        try h.play(c, "d5e7")
        #expect(c.puzzleState == .wrong)
        c.retryPuzzle()
        try h.play(c, fork.solution)
        #expect(c.puzzleState == .solved)
    }

    @Test("a mate-in-two asks the engine whether mate is still forced after the first move")
    func mateInTwo() async throws {
        let ladder = try puzzle("m2-ladder")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: ladder))
        h.ai.scriptHint("h8g8", -200_000)
        try h.play(c, ladder.solution)
        await h.settle()
        #expect(c.puzzleState == .solving)
        #expect(h.ai.hintRequests.count == 1)

        c.retryPuzzle()
        h.ai.scriptHint("h8g8", 0)
        try h.play(c, "a1a2")
        await h.settle()
        #expect(c.puzzleState == .wrong)
    }

    @Test("a recorded mistake replays as a personalized puzzle")
    func mistakeReplay() throws {
        let backRank = try puzzle("m1-backrank")
        let mistake = RecordedMistake(fen: backRank.fen, playedUci: "a1a7", bestUci: "a1a8", cpLoss: 900,
                                      date: 0, playerColor: .white)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(mistake: mistake))
        #expect(c.puzzleState == .solving)
        try h.play(c, "a1a8")
        #expect(c.puzzleState == .solved)
        #expect(h.state.progress.xp == 15)
        #expect(h.state.progress.solvedPuzzles == [])
        #expect(h.state.progress.counters.puzzlesSolved == 1)
    }

    @Test("solving the daily puzzle advances the streak")
    func daily() throws {
        let backRank = try puzzle("m1-backrank")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank, isDaily: true))
        try h.play(c, "a1a8")
        #expect(h.state.progress.dailyStreak == 1)
        #expect(h.state.progress.lastDailyDate == "2026-06-01")
    }
}

@MainActor
@Suite("GameController: constraint games and drills")
struct ConstraintAndDrillTests {
    @Test("silent queen: the player may not move the queen")
    func silentQueen() throws {
        let sq = try constraint(.silentQueen)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .constraint, challenge: ChallengeContext(constraint: sq),
                      startFen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        #expect(c.moveAllowedByConstraint(try #require(c.uciToMove("d1h5"))) == false)
        #expect(c.moveAllowedByConstraint(try #require(c.uciToMove("g1f3"))))
        #expect(c.hintsLeft == 0)
    }

    @Test("rook odds starts from the odds position")
    func rookOdds() throws {
        let odds = try constraint(.rookOdds)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .constraint, challenge: ChallengeContext(constraint: odds))
        #expect(c.game.position.fen == odds.fen)
    }

    @Test("knight's honor completes only when a knight delivers mate")
    func knightsHonor() throws {
        let km = try constraint(.knightMate)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .constraint, challenge: ChallengeContext(constraint: km), startFen: "6rk/6pp/8/6N1/8/8/8/K7 w - - 0 1")
        try h.play(c, "g5f7")
        #expect(c.game.result?.kind == .checkmate)
        #expect(c.game.result?.winner == .white)
        #expect(h.state.progress.completedConstraints == [km.id])
        #expect(h.state.progress.xp == km.xp)
        #expect(h.state.progress.counters.checkmates == 1)
        #expect(h.state.progress.counters.gamesPlayed == 1)
        #expect(h.state.archive.count == 1)
        #expect(h.state.archive.first?.mode == .constraint)

        // the same mate delivered by a rook does not count
        h.state.progress = PlayerProgress()
        try c.newGame(mode: .constraint, challenge: ChallengeContext(constraint: km), startFen: "7k/6pp/8/8/8/8/6N1/R6K w - - 0 1")
        try h.play(c, "a1a8")
        #expect(c.game.result?.kind == .checkmate)
        #expect(h.state.progress.completedConstraints == [])
    }

    @Test("a won drill is completed once and pays its XP")
    func wonDrill() throws {
        let drill = Drill(id: "test-drill", title: "Mate the king", fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1",
                          playerColor: .white, goal: .win, description: "", xp: 30)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .drill, challenge: ChallengeContext(drill: drill))
        #expect(c.aiSkill == 20)
        #expect(c.playerColor == .white)
        try h.play(c, "a1a8")
        #expect(h.state.progress.completedDrills == ["test-drill"])
        #expect(h.state.progress.xp == 30)
        try c.newGame(mode: .drill, challenge: ChallengeContext(drill: drill))
        try h.play(c, "a1a8")
        #expect(h.state.progress.xp == 30)
    }

    @Test("a drill to hold the draw is satisfied by a draw")
    func holdDrill() throws {
        let drill = Drill(id: "test-hold", title: "Hold", fen: "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1",
                          playerColor: .white, goal: .draw, description: "", xp: 20)
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .drill, challenge: ChallengeContext(drill: drill))
        try h.play(c, "f1f7")
        #expect(c.game.result?.kind == .stalemate)
        #expect(h.state.progress.completedDrills == ["test-hold"])
        #expect(h.state.progress.xp == 20)
    }
}

@MainActor
@Suite("GameController: ending a game")
struct EndingTests {
    @Test("resignation vs the AI updates record, rating, XP and the archive")
    func resignVsAi() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        let before = h.state.model.rating
        c.resign()
        #expect(c.game.status == .finished)
        #expect(c.game.result?.kind == .resignation)
        #expect(c.game.result?.winner == .black)
        #expect(h.state.progress.counters.gamesPlayed == 1)
        #expect(h.state.progress.counters.gamesWon == 0)
        #expect(h.state.model.losses == 1)
        #expect(h.state.model.rating < before)
        #expect(h.state.progress.xp == 10)
        #expect(h.state.archive.count == 1)
        #expect(h.state.archive.first?.score == "0-1")
        #expect(h.state.archive.first?.pgn.contains("[White \"You\"]") == true)
        #expect(h.state.archive.first?.pgn.contains("[Black \"AI (\(c.aiElo))\"]") == true)
        #expect(h.state.saved == nil)
        #expect(c.postGame?.offersReady == true)
        #expect(h.ai.analyzeRequests.isEmpty) // too short to analyse

        c.resign() // idempotent
        #expect(h.state.progress.counters.gamesPlayed == 1)
        #expect(h.state.archive.count == 1)
    }

    @Test("pass-and-play: the side on move resigns; draw offers are accepted by the other side")
    func pvpResignAndDraw() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        try h.play(c, "e2e4")
        c.offerDraw()
        #expect(c.game.drawOffer == .black)
        c.declineDraw()
        #expect(c.game.drawOffer == nil)
        c.offerDraw()
        c.acceptDraw()
        #expect(c.game.result?.kind == .agreement)
        #expect(h.state.progress.counters.gamesPlayed == 1)
        #expect(h.state.model.draws == 0) // pass-and-play never touches the player model
        #expect(h.state.archive.first?.pgn.contains("[White \"White\"]") == true)

        try c.newGame(mode: .pvp)
        try h.play(c, "e2e4")
        c.resign()
        #expect(c.game.result?.winner == .white)
    }

    @Test("the AI accepts a draw only when clearly worse")
    func aiAcceptsDraw() async throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        h.ai.scriptHint("e2e4", 50) // AI only slightly worse
        c.offerDraw()
        await h.settle()
        #expect(c.game.status == .active)
        #expect(c.game.drawOffer == nil)

        h.ai.scriptHint("e2e4", 300) // AI clearly worse
        c.offerDraw()
        await h.settle()
        #expect(c.game.result?.kind == .agreement)
        #expect(h.state.model.draws == 1)
        #expect(h.state.progress.xp == 20)
    }
}

@MainActor
@Suite("GameController: clocks")
struct ClockIntegrationTests {
    @Test("start on the first move, press with increment, and are saved for resume")
    func startAndPress() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp, timeControl: timePresets[1]) // Blitz 3+2
        #expect(c.timerOn)
        let clock = try #require(c.clock)
        #expect(clock.active == nil)
        try h.play(c, "e2e4")
        #expect(clock.active == .black)
        h.time.advance(ms: 3000)
        try h.play(c, "e7e5")
        #expect(c.game.history[1].clockMs == 177_000)
        #expect(clock.remaining[.black] == 180_000 - 3000 + 2000)
        #expect(clock.active == .white)
        #expect(h.state.saved?.clockRemaining == ClockRemaining(white: 180_000, black: 179_000))
        clock.dispose()
    }

    @Test("a flag fall ends the game on time and counts as a win on time")
    func flagFall() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp, timeControl: timePresets[0]) // Bullet 1+0
        try h.play(c, "e2e4")
        h.time.advance(ms: 61_000)
        #expect(c.game.status == .finished)
        #expect(c.game.result?.kind == .timeout)
        #expect(c.game.result?.winner == .white)
        #expect(h.state.progress.counters.winsOnTime == 1)
        #expect(h.state.progress.badges.contains("flag-win"))
        #expect(h.state.saved == nil)
    }

    @Test("can be switched off before the first move but not after")
    func switchOff() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp, timeControl: timePresets[2])
        c.setTimerOn(false)
        #expect(c.clock == nil)
        #expect(c.timeControl == nil)
        try c.newGame(mode: .pvp, timeControl: timePresets[2])
        try h.play(c, "e2e4")
        c.setTimerOn(false)
        #expect(c.clock != nil)
        #expect(c.timerOn)
        c.clock?.dispose()
    }

    @Test("the AI budgets less thinking time when short on clock")
    func budgetsLess() async throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white, timeControl: TimeControl(name: "t", baseMs: 4000, incrementMs: 0))
        try h.play(c, "e2e4")
        await h.drain()
        #expect(h.ai.moveRequests.first?.moveTimeMs == 150) // max(150, 4000 / 40)
        c.clock?.dispose()
    }
}

@MainActor
@Suite("GameController: resume")
struct ResumeTests {
    @Test("restores position, mode and clocks, then hands the move to the AI")
    func restores() async throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white, timeControl: timePresets[2])
        try h.play(c, "e2e4")
        h.time.advance(ms: 1500)
        c.save()
        c.clock?.dispose()
        let saved = try h.savedRoundTrip()
        #expect(saved.clockRemaining == ClockRemaining(white: 600_000, black: 598_500))

        let c2 = h.controller()
        #expect(c2.resume(saved))
        #expect(c2.game.uciLine() == ["e2e4"])
        #expect(c2.mode == .ai)
        #expect(c2.playerColor == .white)
        #expect(c2.aiElo == c.aiElo)
        let clock = try #require(c2.clock)
        #expect(clock.remaining == ClockRemaining(white: 600_000, black: 598_500))
        #expect(clock.active == .black)
        #expect(c2.thinking)
        await h.drain()
        #expect(h.ai.moveRequests.count == 2)
        clock.dispose()
    }

    @Test("restores a challenge by id")
    func restoresChallenge() throws {
        let backRank = try puzzle("m1-backrank")
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank))
        let saved = try h.savedRoundTrip()
        #expect(saved.challengeId == backRank.id)
        let c2 = h.controller()
        #expect(c2.resume(saved))
        #expect(c2.challenge?.puzzle?.id == backRank.id)
        #expect(c2.puzzleState == .solving)
        #expect(c2.game.startFEN == backRank.fen)
    }

    @Test("refuses a corrupted save")
    func refusesCorrupted() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        var saved = try h.savedRoundTrip()
        saved.uciMoves = ["e2e4", "zz99"]
        #expect(h.controller().resume(saved) == false)
    }
}

@MainActor
@Suite("GameController: hints")
struct HintTests {
    @Test("cost one of three and come from the engine")
    func costOne() async throws {
        let h = Harness()
        h.ai.scriptHint("e2e4", 30)
        let c = h.controller()
        try c.newGame(mode: .pvp)
        await c.useHint()
        #expect(c.hintsLeft == 2)
        #expect(h.state.progress.counters.hintsUsed == 1)
        #expect(c.hintMove?.uci == "e2e4")
        #expect(h.state.saved?.hintsLeft == 2)
        try h.play(c, "e2e4")
        #expect(c.hintMove == nil)
    }

    @Test("are unavailable when exhausted or when it is not the human's turn")
    func unavailable() async throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .black) // AI to move
        await c.useHint()
        #expect(h.ai.hintRequests.isEmpty)
        try c.newGame(mode: .pvp)
        c.hintsLeft = 0
        await c.useHint()
        #expect(h.ai.hintRequests.isEmpty)
    }
}

@MainActor
@Suite("GameController: post-game analysis")
struct PostGameAnalysisTests {
    @Test("grades a finished AI game, records big mistakes and attaches the analysis to the archive")
    func grades() async throws {
        let h = Harness()
        h.ai.script("e7e5", "d8h4")
        h.ai.scriptAnalysis([
            analysed("f2f3", "e2e4", 60), analysed("e7e5", "e7e5", 0),
            analysed("g2g4", "d2d4", 900), analysed("d8h4", "d8h4", 0),
        ])
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "f2f3")
        await h.settle()
        try h.play(c, "g2g4")
        await h.settle()
        #expect(c.game.result?.kind == .checkmate)
        #expect(c.game.result?.winner == .black)
        #expect(h.ai.analyzeRequests == [
            AnalyzeRequest(startFEN: Position.startFEN, uciMoves: ["f2f3", "e7e5", "g2g4", "d8h4"], perMoveMs: 250),
        ])
        await h.settle()
        #expect(!c.analysisPending)
        #expect(c.analysis?.count == 4)
        #expect(h.state.mistakes.count == 1)
        let mistake = try #require(h.state.mistakes.first)
        #expect(mistake.playedUci == "g2g4")
        #expect(mistake.bestUci == "d2d4")
        #expect(mistake.cpLoss == 900)
        #expect(mistake.playerColor == .white)
        #expect(mistake.date == Harness.epoch + 1000) // stamped when the analysis lands, two settles in
        #expect(mistake.fen.hasPrefix("rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w"))
        #expect(h.state.archive.first?.analysis?.count == 4)
        #expect(h.state.model.features.avgCpLoss == 480)
        #expect(h.state.model.losses == 1)
        #expect(h.state.progress.xp == 10)
    }

    @Test("survives an analysis failure")
    func survivesFailure() async throws {
        let h = Harness()
        h.ai.script("e7e5", "d8h4")
        h.ai.failNextAnalysis()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "f2f3")
        await h.settle()
        try h.play(c, "g2g4")
        await h.settle()
        #expect(c.game.status == .finished)
        #expect(!c.analysisPending)
        #expect(c.analysis == nil)
        #expect(h.state.archive.count == 1)
        #expect(h.state.archive.first?.analysis == nil)
    }
}

// Swift-only: the parts of controller.ts the TS suite takes on trust (feedback calls, `Date.now()`
// stamps) and the cancellation the Swift port adds on top of the `moveSeq` guard.

@MainActor
@Suite("GameController: feedback and cancellation")
struct FeedbackAndCancellationTests {
    @Test("moves, captures, checks, castling and promotions play the feedback.ts sounds and haptics")
    func moveFeedback() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .pvp)
        try h.play(c, "e2e4")
        #expect(h.feedback.sounds == [.move])
        #expect(h.feedback.haptics == [.light])
        try h.play(c, "d7d5")
        h.feedback.reset()
        try h.play(c, "e4d5")
        #expect(h.feedback.sounds == [.capture])
        #expect(h.feedback.haptics == [.medium])

        try c.newGame(mode: .pvp, startFen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
        h.feedback.reset()
        try h.play(c, "a1a8")
        #expect(h.feedback.sounds == [.check])

        try c.newGame(mode: .pvp, startFen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        h.feedback.reset()
        try h.play(c, "e1g1")
        #expect(c.game.sanLine() == ["O-O"])
        #expect(h.feedback.sounds == [.castle])

        try c.newGame(mode: .pvp, startFen: "8/P6k/6p1/8/8/8/8/K7 w - - 0 1")
        h.feedback.reset()
        try h.play(c, "a7a8n")
        #expect(h.feedback.sounds == [.promote])
        #expect(h.state.progress.counters.underpromotions == 1)

        try c.newGame(mode: .pvp, startFen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        h.feedback.reset()
        try h.play(c, "e5d6")
        #expect(h.feedback.sounds == [.capture])
        #expect(h.feedback.haptics == [.medium])
        #expect(h.state.progress.counters.enPassants == 1)
    }

    @Test("game endings: win, loss, pass-and-play and puzzle outcomes")
    func endFeedback() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white, startFen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        h.feedback.reset()
        try h.play(c, "a1a8")
        #expect(c.game.result?.kind == .checkmate)
        #expect(h.feedback.sounds == [.gameWin]) // the mating move itself is silent
        #expect(h.feedback.haptics == [.light, .success])

        try c.newGame(mode: .ai, playerColor: .white)
        h.feedback.reset()
        c.resign()
        #expect(h.feedback.sounds == [.gameLoss])
        #expect(h.feedback.haptics == [.warning])

        try c.newGame(mode: .pvp)
        h.feedback.reset()
        c.resign()
        #expect(h.feedback.sounds == [.gameDraw]) // every pass-and-play ending uses the draw sound

        let backRank = try puzzle("m1-backrank")
        try c.newGame(mode: .puzzle, challenge: ChallengeContext(puzzle: backRank))
        h.feedback.reset()
        try h.play(c, "a1a7")
        #expect(h.feedback.sounds == [.move, .error])
        #expect(h.feedback.haptics == [.light, .warning])
        c.retryPuzzle()
        h.feedback.reset()
        try h.play(c, "a1a8")
        // controller.ts plays the win twice on a mating puzzle move: once in puzzleSolved, once in onGameEnd
        #expect(h.feedback.sounds == [.gameWin, .gameWin])
        #expect(h.feedback.haptics == [.light, .success, .success])
    }

    @Test("the low-time warning sounds for the player's clock, not the AI's")
    func lowTime() throws {
        let h = Harness()
        let c = h.controller()
        let short = TimeControl(name: "short", baseMs: 25_000, incrementMs: 0)
        try c.newGame(mode: .ai, playerColor: .white, timeControl: short)
        try h.play(c, "e2e4") // the AI's clock runs while it thinks
        h.feedback.reset()
        h.time.advance(ms: 6000)
        #expect(c.clock?.remaining[.black] == 19_000)
        #expect(h.feedback.sounds == [])
        c.clock?.dispose()

        try c.newGame(mode: .pvp, timeControl: short)
        try h.play(c, "e2e4")
        h.feedback.reset()
        h.time.advance(ms: 6000)
        #expect(h.feedback.sounds == [.lowTime])
        #expect(h.feedback.haptics == [.warning])
        c.clock?.dispose()
    }

    @Test("the archive and the save carry the wall-clock timestamp")
    func timestamps() throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        #expect(h.state.saved?.savedAt == Harness.epoch)
        h.time.advance(ms: 2500)
        c.resign()
        #expect(h.state.archive.first?.date == Harness.epoch + 2500)
        #expect(h.state.archive.first?.pgn.contains("[Date \"2026.06.01\"]") == true)
    }

    @Test("a new game, undo, resignation or dispose cancels the pending AI request")
    func cancellation() async throws {
        let h = Harness()
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .black)
        await h.drain()
        #expect(h.ai.hangingCount == 1)
        try c.newGame(mode: .pvp)
        await h.drain()
        #expect(h.ai.hangingCount == 0)
        #expect(c.inflightRequests == 0)

        try c.newGame(mode: .ai, playerColor: .black)
        await h.drain()
        #expect(h.ai.hangingCount == 1)
        c.resign()
        await h.drain()
        #expect(h.ai.hangingCount == 0)
        #expect(c.game.history.isEmpty) // no failsafe move after a cancellation

        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "e2e4")
        await h.drain()
        #expect(h.ai.hangingCount == 1)
        c.undo()
        await h.drain()
        #expect(h.ai.hangingCount == 0)
        #expect(c.game.history.isEmpty)
        #expect(!c.thinking)

        try c.newGame(mode: .ai, playerColor: .black)
        await h.drain()
        c.dispose()
        await h.drain()
        #expect(h.ai.hangingCount == 0)
        #expect(h.ai.moveRequests.count == 4)
    }

    @Test("dispose cancels a pending post-game analysis")
    func disposeCancelsAnalysis() async throws {
        let h = Harness()
        h.ai.script("e7e5", "d8h4")
        let c = h.controller()
        try c.newGame(mode: .ai, playerColor: .white)
        try h.play(c, "f2f3")
        await h.settle()
        try h.play(c, "g2g4")
        await h.settle()
        #expect(c.analysisPending)
        #expect(h.ai.hangingCount == 1)
        c.dispose()
        await h.drain()
        #expect(h.ai.hangingCount == 0)
        #expect(!c.analysisPending)
        #expect(c.analysis == nil)
    }
}

@MainActor
@Suite("ManualTimeSource timeouts")
struct ManualTimeSourceTimeoutTests {
    @MainActor
    final class Log {
        var fired: [Int] = []
    }

    @Test("one-shot timers fire once at their due time, in order, and can be cancelled")
    func oneShot() {
        let time = ManualTimeSource(nowMs: 1000)
        let log = Log()
        _ = time.schedule(afterMs: 450) { log.fired.append(time.nowMs) }
        _ = time.schedule(afterMs: 0) { log.fired.append(time.nowMs) }
        let cancelled = time.schedule(afterMs: 100) { log.fired.append(-1) }
        cancelled.cancel()
        #expect(time.scheduledTimerCount == 2)
        time.advance(ms: 449)
        #expect(log.fired == [1000])
        time.advance(ms: 1)
        #expect(log.fired == [1000, 1450])
        #expect(time.scheduledTimerCount == 0)
        time.advance(ms: 1000)
        #expect(log.fired == [1000, 1450])
        #expect(time.nowMs == 2450)
    }

    @Test("the wall clock follows nowMs as Unix milliseconds")
    func wallClock() {
        let time = ManualTimeSource(nowMs: Harness.epoch)
        #expect(time.now == Date(timeIntervalSince1970: 1_780_304_400))
        time.advance(ms: 1500)
        #expect(time.now.timeIntervalSince1970 == 1_780_304_401.5)
    }
}
