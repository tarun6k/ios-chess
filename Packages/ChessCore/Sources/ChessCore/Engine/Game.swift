// Ported 1:1 from src/engine/game.ts.
//
// TypeScript name → Swift name
//   GameStatus / ResultKind / GameResult / HistoryEntry → same names (ResultKind raw values are the TS strings)
//   Game.pos / startFen / history / result / drawOffer → position / startFEN / history / result / drawOffer
//   legalMoves() / inCheck() / repetitionCount() / claimableDraw() → legalMoves() / isInCheck() / repetitionCount() / claimableDraw()
//   play(move, meta) / playSAN(san, meta)     → play(_:clockMs:thinkMs:) / playSAN(_:clockMs:thinkMs:)
//   undo / resign / timeout / offerDraw / declineDraw / acceptDraw / claimDraw → same names
//   positionAt / sanLine / uciLine / capturedBy → same names

/// Game lifecycle: setup → active → finished (result set) → review happens on top.
public enum GameStatus: String, Hashable, Sendable {
    case active
    case finished
}

/// TS `ResultKind` string union; raw values are the TS strings.
public enum ResultKind: String, Hashable, Sendable, Codable, CaseIterable {
    case checkmate
    case stalemate
    case resignation
    case timeout
    case timeoutDraw = "timeout-draw"
    case agreement
    case threefold
    case fivefold
    case fiftyMove = "fifty-move"
    case seventyFiveMove = "seventy-five-move"
    case insufficient
    case deadPosition = "dead-position"
    case aborted
}

public struct GameResult: Hashable, Sendable {
    /// "1-0" | "0-1" | "1/2-1/2" | "*"
    public var score: String
    public var kind: ResultKind
    public var winner: PieceColor?
    public var message: String

    public init(score: String, kind: ResultKind, winner: PieceColor?, message: String) {
        self.score = score
        self.kind = kind
        self.winner = winner
        self.message = message
    }
}

public struct HistoryEntry: Hashable, Sendable {
    public var move: Move
    public var san: String
    /// FEN after the move.
    public var fen: String
    /// Signed captured piece, or `.empty` (TS `0`).
    public var captured: Piece
    /// Repetition key after the move.
    public var key: String
    /// ms remaining on the mover's clock after the move (if clocks in use).
    public var clockMs: Int?
    /// Wall-clock time the mover spent on this move, ms.
    public var thinkMs: Int?

    public init(move: Move, san: String, fen: String, captured: Piece, key: String, clockMs: Int? = nil, thinkMs: Int? = nil) {
        self.move = move
        self.san = san
        self.fen = fen
        self.captured = captured
        self.key = key
        self.clockMs = clockMs
        self.thinkMs = thinkMs
    }
}

/// TS `class Game`, as a value type: copying a game copies its whole state.
public struct Game: Sendable {
    /// TS `pos`.
    public private(set) var position: Position
    public private(set) var history: [HistoryEntry] = []
    /// TS `startFen`.
    public let startFEN: String
    public private(set) var result: GameResult? = nil
    /// Side that has an open draw offer.
    public private(set) var drawOffer: PieceColor? = nil
    private var repetition: [String: Int] = [:]
    /// The position the game started from, replayed by `positionAt`.
    private let startPosition: Position

    /// TS `new Game()`: the standard start position.
    public init() {
        do {
            try self.init(fen: Position.startFEN)
        } catch {
            preconditionFailure("the start FEN is valid: \(error)")
        }
    }

    /// TS `new Game(fen)`; throws `FENError` like the TS constructor.
    public init(fen: String) throws {
        startFEN = fen
        position = try Position(fen: fen)
        startPosition = position
        repetition[position.hashKey] = 1
        checkAutomaticEnd()
    }

    public var status: GameStatus { result != nil ? .finished : .active }
    public var turn: PieceColor { position.turn }

    public func legalMoves() -> [Move] {
        result != nil ? [] : position.generateLegalMoves()
    }

    /// TS `inCheck()`.
    public func isInCheck() -> Bool { position.isInCheck() }

    /// Number of times the current position has occurred.
    public func repetitionCount() -> Int {
        repetition[position.hashKey] ?? 1
    }

    /// Can the side to move CLAIM a draw right now (threefold or 50-move)?
    public func claimableDraw() -> ResultKind? {
        if result != nil { return nil }
        if repetitionCount() >= 3 { return .threefold }
        if position.halfmove >= 100 { return .fiftyMove }
        return nil
    }

    /// Play a legal move. Returns the SAN, or nil if illegal / game over.
    @discardableResult
    public mutating func play(_ move: Move, clockMs: Int? = nil, thinkMs: Int? = nil) -> String? {
        if result != nil { return nil }
        let legals = position.generateLegalMoves()
        if !legals.contains(move) { return nil }
        let san = toSAN(position, move, legalMoves: legals)
        let captured = move.flags.contains(.enPassant)
            ? position.board[move.to + (position.turn == .white ? -8 : 8)]
            : position.board[move.to]
        position.makeMove(move)
        let key = position.hashKey
        repetition[key] = (repetition[key] ?? 0) + 1
        history.append(HistoryEntry(move: move, san: san, fen: position.fen, captured: captured, key: key,
                                    clockMs: clockMs, thinkMs: thinkMs))
        drawOffer = nil // making a move implicitly declines any pending offer
        checkAutomaticEnd()
        return san
    }

    @discardableResult
    public mutating func playSAN(_ san: String, clockMs: Int? = nil, thinkMs: Int? = nil) -> String? {
        if result != nil { return nil }
        guard let m = fromSAN(position, san) else { return nil }
        return play(m, clockMs: clockMs, thinkMs: thinkMs)
    }

    /// Undo the last ply. Returns true if something was undone.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let entry = history.popLast() else { return false }
        let count = repetition[entry.key] ?? 1
        if count <= 1 { repetition[entry.key] = nil } else { repetition[entry.key] = count - 1 }
        position.unmakeMove()
        result = nil
        drawOffer = nil
        return true
    }

    public mutating func resign(_ color: PieceColor) {
        if result != nil { return }
        let winner = color.opponent
        setResult(winner == .white ? "1-0" : "0-1", .resignation, winner,
                  (winner == .white ? "White" : "Black") + " wins by resignation")
    }

    /// Flag fall for `color`. Draw if the opponent cannot possibly mate (FIDE 6.9).
    public mutating func timeout(_ color: PieceColor) {
        if result != nil { return }
        let opp = color.opponent
        if position.hasMatingPotential(opp) {
            setResult(opp == .white ? "1-0" : "0-1", .timeout, opp,
                      (opp == .white ? "White" : "Black") + " wins on time")
        } else {
            setResult("1/2-1/2", .timeoutDraw, nil,
                      "Draw — flag fell but " + (opp == .white ? "White" : "Black") + " cannot checkmate")
        }
    }

    public mutating func offerDraw(_ color: PieceColor) {
        if result == nil { drawOffer = color }
    }

    public mutating func declineDraw() { drawOffer = nil }

    @discardableResult
    public mutating func acceptDraw() -> Bool {
        if result != nil || drawOffer == nil { return false }
        drawOffer = nil
        setResult("1/2-1/2", .agreement, nil, "Draw by agreement")
        return true
    }

    /// Claim threefold / fifty-move draw (only when actually claimable).
    @discardableResult
    public mutating func claimDraw() -> Bool {
        guard let kind = claimableDraw() else { return false }
        setResult("1/2-1/2", kind, nil,
                  kind == .threefold ? "Draw by threefold repetition" : "Draw by the fifty-move rule")
        return true
    }

    private mutating func setResult(_ score: String, _ kind: ResultKind, _ winner: PieceColor?, _ message: String) {
        result = GameResult(score: score, kind: kind, winner: winner, message: message)
    }

    private mutating func checkAutomaticEnd() {
        if result != nil { return }
        if !position.hasLegalMoves {
            if position.isInCheck() {
                let winner = position.turn.opponent
                setResult(winner == .white ? "1-0" : "0-1", .checkmate, winner,
                          (winner == .white ? "White" : "Black") + " wins by checkmate")
            } else {
                setResult("1/2-1/2", .stalemate, nil, "Draw by stalemate")
            }
            return
        }
        if (repetition[position.hashKey] ?? 0) >= 5 {
            setResult("1/2-1/2", .fivefold, nil, "Draw by fivefold repetition")
            return
        }
        if position.halfmove >= 150 {
            setResult("1/2-1/2", .seventyFiveMove, nil, "Draw by the seventy-five-move rule")
            return
        }
        if position.isInsufficientMaterial {
            setResult("1/2-1/2", .insufficient, nil, "Draw — insufficient material")
            return
        }
        if position.isDeadPosition {
            setResult("1/2-1/2", .deadPosition, nil, "Draw — dead position")
        }
    }

    /// Position after ply `n` (0 = start) as a fresh Position — for review/analysis.
    public func positionAt(_ ply: Int) -> Position {
        var p = startPosition
        var i = 0
        while i < ply && i < history.count {
            p.makeMove(history[i].move)
            i += 1
        }
        return p
    }

    public func sanLine() -> [String] { history.map(\.san) }
    public func uciLine() -> [String] { history.map(\.move.uci) }

    /// Types of the pieces `color` has captured, in move order.
    public func capturedBy(_ color: PieceColor) -> [PieceType] {
        history
            .filter { !$0.captured.isEmpty && $0.captured.color != color }
            .map(\.captured.type)
    }
}
