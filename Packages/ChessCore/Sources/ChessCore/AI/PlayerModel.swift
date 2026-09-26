// Ported 1:1 from src/ai/playerModel.ts — the persistent model of the human player: style, rating,
// openings, weaknesses. Built up after every finished game from the move record + post-game analysis.
//
// TypeScript name → Swift name
//   StyleLabel / WeaknessKey             → enums whose raw values are the TS strings
//   OpeningStat / StyleFeatures          → same names
//   Record<WeaknessKey, number>          → WeaknessCounts (one counter per key, JSON object with the TS keys)
//   PlayerModel                          → struct PlayerModel; `newPlayerModel()` → `PlayerModel()`
//   roll                                 → roll (file-private)
//   GameFacts / extractFacts             → same names
//   extractWeaknesses                    → same name; the TS `Partial<Record>` is `[WeaknessKey: Int]`
//   classifyStyle                        → same name, returning `StyleClassification`
//   updateRating(model, aiElo, score)    → updateRating(&model, aiElo:score:now:) — `Date.now()` is injected
//   updateModelAfterGame(model, …, opts) → updateModelAfterGame(&model, game:playerColor:analysis:vsAI:aiElo:now:)
//   topWeaknesses(model, n)              → topWeaknesses(_:n:) returning [WeaknessCount]
//
// JSON: `PlayerModel` encodes exactly like `JSON.stringify(model)` (same keys; `lastAdaptation` is omitted
// when nil). Decoding applies store.ts `loadAll`'s `{ ...newPlayerModel(), ...model }`: a missing top-level
// key takes its default, nested objects are read as stored.

import Darwin

public enum StyleLabel: String, Codable, Hashable, Sendable, CaseIterable {
    case aggressive
    case tactical
    case positional
    case defensive
    case materialistic
    case balanced
}

/// The cases are in the TS key order of `newPlayerModel().weaknesses`, which `Object.entries` (and so
/// `topWeaknesses`' tie order) follows.
public enum WeaknessKey: String, Codable, Hashable, Sendable, CaseIterable {
    /// outright gave material away
    case hangingPieces = "hanging-pieces"
    /// best move was a tactic (capture/check) but a quiet move was played
    case missedTactics = "missed-tactics"
    /// blunders with the king still on the back rank behind pawns
    case backRank = "back-rank"
    /// errors once material is reduced
    case endgame
    /// errors in the first 8 moves
    case opening
    /// castled late / never, got attacked
    case kingSafety = "king-safety"
}

public struct OpeningStat: Codable, Hashable, Sendable {
    public var name: String
    public var count: Int
    public var asWhite: Int
    public var wins: Int

    public init(name: String, count: Int, asWhite: Int, wins: Int) {
        self.name = name
        self.count = count
        self.asWhite = asWhite
        self.wins = wins
    }
}

public struct StyleFeatures: Codable, Hashable, Sendable {
    public var games: Int
    /// captures per move
    public var avgCaptureRate: Double
    /// ply of first queen move (or 24 if late/never)
    public var avgEarlyQueenPly: Double
    /// ply the player castled (or 30 if never)
    public var avgCastlePly: Double
    public var avgChecksPerGame: Double
    /// pawn advances beyond rank 4 per game
    public var avgPawnStorm: Double
    /// recaptures per capture opportunity
    public var avgTradeRate: Double
    /// accuracy proxy from analysis
    public var avgCpLoss: Double
    public var avgThinkMs: Double

    /// The defaults are `newPlayerModel().features`.
    public init(games: Int = 0, avgCaptureRate: Double = 0, avgEarlyQueenPly: Double = 24, avgCastlePly: Double = 30,
                avgChecksPerGame: Double = 0, avgPawnStorm: Double = 0, avgTradeRate: Double = 0, avgCpLoss: Double = 0,
                avgThinkMs: Double = 0) {
        self.games = games
        self.avgCaptureRate = avgCaptureRate
        self.avgEarlyQueenPly = avgEarlyQueenPly
        self.avgCastlePly = avgCastlePly
        self.avgChecksPerGame = avgChecksPerGame
        self.avgPawnStorm = avgPawnStorm
        self.avgTradeRate = avgTradeRate
        self.avgCpLoss = avgCpLoss
        self.avgThinkMs = avgThinkMs
    }
}

/// TS `Record<WeaknessKey, number>`.
public struct WeaknessCounts: Codable, Hashable, Sendable {
    public var hangingPieces = 0
    public var missedTactics = 0
    public var backRank = 0
    public var endgame = 0
    public var opening = 0
    public var kingSafety = 0

    enum CodingKeys: String, CodingKey {
        case hangingPieces = "hanging-pieces"
        case missedTactics = "missed-tactics"
        case backRank = "back-rank"
        case endgame
        case opening
        case kingSafety = "king-safety"
    }

    public init() {}

    public subscript(key: WeaknessKey) -> Int {
        get {
            switch key {
            case .hangingPieces: return hangingPieces
            case .missedTactics: return missedTactics
            case .backRank: return backRank
            case .endgame: return endgame
            case .opening: return opening
            case .kingSafety: return kingSafety
            }
        }
        set {
            switch key {
            case .hangingPieces: hangingPieces = newValue
            case .missedTactics: missedTactics = newValue
            case .backRank: backRank = newValue
            case .endgame: endgame = newValue
            case .opening: opening = newValue
            case .kingSafety: kingSafety = newValue
            }
        }
    }

    /// TS `Object.entries(model.weaknesses)`: every counter in key order.
    public var entries: [WeaknessCount] {
        WeaknessKey.allCases.map { WeaknessCount(key: $0, count: self[$0]) }
    }
}

/// One element of `topWeaknesses`' result (TS `{ key, count }`).
public struct WeaknessCount: Hashable, Sendable {
    public var key: WeaknessKey
    public var count: Int

    public init(key: WeaknessKey, count: Int) {
        self.key = key
        self.count = count
    }
}

/// TS `{ t: number; rating: number }` of `ratingHistory`.
public struct RatingPoint: Codable, Hashable, Sendable {
    /// `Date.now()` milliseconds.
    public var t: Int
    public var rating: Int

    public init(t: Int, rating: Int) {
        self.t = t
        self.rating = rating
    }
}

public struct PlayerModel: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var rating: Int = 800
    public var ratingHistory: [RatingPoint] = []
    public var wins = 0
    public var losses = 0
    public var draws = 0
    /// >0 winning streak, <0 losing streak
    public var streak = 0
    public var features = StyleFeatures()
    public var weaknesses = WeaknessCounts()
    public var openings: [OpeningStat] = []
    /// last few games' adaptation summaries (for the insights screen)
    public var lastAdaptation: [String]? = nil

    /// TS `newPlayerModel()`.
    public init() {}

    /// store.ts `{ ...newPlayerModel(), ...model }`: absent top-level keys keep their defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? version
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? rating
        ratingHistory = try c.decodeIfPresent([RatingPoint].self, forKey: .ratingHistory) ?? ratingHistory
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? wins
        losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? losses
        draws = try c.decodeIfPresent(Int.self, forKey: .draws) ?? draws
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? streak
        features = try c.decodeIfPresent(StyleFeatures.self, forKey: .features) ?? features
        weaknesses = try c.decodeIfPresent(WeaknessCounts.self, forKey: .weaknesses) ?? weaknesses
        openings = try c.decodeIfPresent([OpeningStat].self, forKey: .openings) ?? openings
        lastAdaptation = try c.decodeIfPresent([String].self, forKey: .lastAdaptation)
    }
}

/// Rolling average with recency weighting.
private func roll(_ prev: Double, _ next: Double, _ games: Int) -> Double {
    let w = min(0.25, 1 / Double(max(1, games)))
    return prev * (1 - w) + next * w
}

public struct GameFacts: Hashable, Sendable {
    public var playerColor: PieceColor
    public var captureRate: Double
    public var earlyQueenPly: Int
    public var castlePly: Int
    public var checks: Int
    public var pawnStorm: Int
    public var tradeRate: Double
    public var avgThinkMs: Double
    public var openingName: String?

    public init(playerColor: PieceColor, captureRate: Double, earlyQueenPly: Int, castlePly: Int, checks: Int,
                pawnStorm: Int, tradeRate: Double, avgThinkMs: Double, openingName: String?) {
        self.playerColor = playerColor
        self.captureRate = captureRate
        self.earlyQueenPly = earlyQueenPly
        self.castlePly = castlePly
        self.checks = checks
        self.pawnStorm = pawnStorm
        self.tradeRate = tradeRate
        self.avgThinkMs = avgThinkMs
        self.openingName = openingName
    }
}

/// Extract per-game style features for the player's side.
public func extractFacts(_ game: Game, playerColor: PieceColor) -> GameFacts {
    var pos = game.positionAt(0)
    var captures = 0, playerMoves = 0, checks = 0, pawnStorm = 0
    var earlyQueenPly = 24, castlePly = 30
    var recaptureChances = 0, recaptures = 0
    var thinkTotal = 0, thinkCount = 0
    var lastCaptureSq = -1

    for (ply, h) in game.history.enumerated() {
        let mover = pos.turn
        let from = h.move.from, to = h.move.to
        let isCapture = !h.captured.isEmpty
        if mover == playerColor {
            playerMoves += 1
            if isCapture { captures += 1 }
            if h.san.contains("+") || h.san.contains("#") { checks += 1 }
            if pos.board[from].type == .queen && ply < 24 && earlyQueenPly == 24 { earlyQueenPly = ply }
            // Exact SAN compare like the TS: castling that gives check ("O-O+") is not recognised.
            if (h.san == "O-O" || h.san == "O-O-O") && castlePly == 30 { castlePly = ply }
            if pos.board[from].type == .pawn {
                let rel = playerColor == .white ? rankOf(to) : 7 - rankOf(to)
                if rel >= 4 { pawnStorm += 1 }
            }
            if lastCaptureSq >= 0 {
                recaptureChances += 1
                if isCapture && to == lastCaptureSq { recaptures += 1 }
            }
            // TS `if (h.thinkMs)`: absent and 0 both skip.
            if let t = h.thinkMs, t != 0 {
                thinkTotal += t
                thinkCount += 1
            }
        }
        lastCaptureSq = isCapture && mover != playerColor ? to : -1
        pos.makeMove(h.move)
    }

    return GameFacts(
        playerColor: playerColor,
        captureRate: playerMoves != 0 ? Double(captures) / Double(playerMoves) : 0,
        earlyQueenPly: earlyQueenPly,
        castlePly: castlePly,
        checks: checks,
        pawnStorm: pawnStorm,
        tradeRate: recaptureChances != 0 ? Double(recaptures) / Double(recaptureChances) : 0,
        avgThinkMs: thinkCount != 0 ? Double(thinkTotal) / Double(thinkCount) : 0,
        openingName: identifyOpening(game.sanLine())?.name
    )
}

/// TS `game.result?.winner !== null && game.result?.winner !== playerColor`: true when the game has no
/// result yet (`undefined !== null`) or the opponent won; false for a draw or a player win.
private func lostOrUnfinished(_ game: Game, playerColor: PieceColor) -> Bool {
    guard let result = game.result else { return true }
    guard let winner = result.winner else { return false }
    return winner != playerColor
}

/// TS `game.result?.winner === playerColor`.
private func won(_ game: Game, playerColor: PieceColor) -> Bool {
    game.result?.winner == playerColor
}

/// TS `game.result?.winner === null || game.result?.winner === undefined`: a draw, or no result at all.
private func drew(_ game: Game) -> Bool {
    game.result?.winner == nil
}

/// Classify weaknesses from the analysis of the player's moves.
public func extractWeaknesses(_ game: Game, playerColor: PieceColor, analysis: [AnalyzedMove]) -> [WeaknessKey: Int] {
    var out: [WeaknessKey: Int] = [:]
    func bump(_ k: WeaknessKey) { out[k, default: 0] += 1 }
    var pos = game.positionAt(0)

    for (ply, a) in analysis.enumerated() {
        let mover = pos.turn
        guard ply < game.history.count else { continue } // TS `if (!h) return`
        let h = game.history[ply]
        if mover == playerColor && a.cpLoss >= 120 {
            // Where in the game?
            if ply < 16 {
                bump(.opening)
            } else {
                var nonPawnMaterial = 0
                for sq in 0..<64 {
                    let p = pos.board[sq]
                    if !p.isEmpty && p.type != .pawn && p.type != .king { nonPawnMaterial += 1 }
                }
                if nonPawnMaterial <= 6 { bump(.endgame) }
            }
            // What kind of mistake?
            let bestWasTactic = a.bestUci != a.uci &&
                (isCaptureUci(pos, a.bestUci) || sanGivesCheck(pos, a.bestUci))
            if bestWasTactic { bump(.missedTactics) }
            if a.cpLoss >= 250 && !isCaptureUci(pos, a.uci) { bump(.hangingPieces) }
            // Back rank: king on home rank behind own pawns while blundering
            let k = pos.kingSquare(playerColor)
            let home = playerColor == .white ? 0 : 7
            if a.cpLoss >= 250 && rankOf(k) == home {
                let dir = playerColor == .white ? 8 : -8
                let f = fileOf(k)
                var sealed = true
                for df in -1...1 {
                    let ff = f + df
                    if ff < 0 || ff > 7 { continue }
                    let s = k + dir + df
                    if s < 0 || s > 63 || pos.board[s].isEmpty {
                        sealed = false
                        break
                    }
                }
                if sealed { bump(.backRank) }
            }
        }
        pos.makeMove(h.move)
    }

    // King safety: never castled and got mated/attacked
    let facts = extractFacts(game, playerColor: playerColor)
    if facts.castlePly >= 30 && lostOrUnfinished(game, playerColor: playerColor) {
        out[.kingSafety, default: 0] += 1
    }
    return out
}

private func isCaptureUci(_ pos: Position, _ uci: String) -> Bool {
    // JS string indexing works in UTF-16 code units.
    let u = Array(uci.utf16)
    if u.count < 4 { return false }
    let to = (Int(u[2]) - 97) + (Int(u[3]) - 49) * 8
    // TS `pos.board[to] !== EMPTY` on an out-of-range Int8Array index compares `undefined`, which is truthy.
    guard to >= 0 && to < 64 else { return true }
    return !pos.board[to].isEmpty
}

private func sanGivesCheck(_ pos: Position, _ uci: String) -> Bool {
    // cheap proxy: does the best move capture near the king or is it a promotion?
    uci.utf16.count == 5
}

/// TS `{ label, scores }` of `classifyStyle`.
public struct StyleClassification: Hashable, Sendable {
    public var label: StyleLabel
    /// aggressive, tactical, positional, defensive, materialistic.
    public var scores: [StyleLabel: Int]

    public init(label: StyleLabel, scores: [StyleLabel: Int]) {
        self.label = label
        self.scores = scores
    }
}

/// Style classification from accumulated features.
public func classifyStyle(_ f: StyleFeatures) -> StyleClassification {
    let aggression =
        (f.avgCaptureRate > 0.18 ? 1 : 0) + (f.avgEarlyQueenPly < 10 ? 1 : 0) +
        (f.avgChecksPerGame > 3 ? 1 : 0) + (f.avgPawnStorm > 5 ? 1 : 0)
    let tactical = (f.avgCaptureRate > 0.22 ? 2 : f.avgCaptureRate > 0.16 ? 1 : 0) + (f.avgChecksPerGame > 4 ? 1 : 0)
    let positional = (f.avgCastlePly < 14 ? 1 : 0) + (f.avgCaptureRate < 0.14 ? 1 : 0) + (f.avgPawnStorm < 3 ? 1 : 0)
    let defensive = (f.avgEarlyQueenPly > 16 ? 1 : 0) + (f.avgChecksPerGame < 2 ? 1 : 0) + (f.avgCaptureRate < 0.12 ? 1 : 0)
    let materialistic = (f.avgTradeRate > 0.6 ? 2 : f.avgTradeRate > 0.45 ? 1 : 0) + (f.avgCaptureRate > 0.2 ? 1 : 0)

    // `Object.entries(scores).sort((a, b) => b[1] - a[1])` is a stable sort, so on a tie the earlier
    // entry in this order wins.
    let ordered: [(label: StyleLabel, score: Int)] = [
        (.aggressive, aggression), (.tactical, tactical), (.positional, positional),
        (.defensive, defensive), (.materialistic, materialistic),
    ]
    var top = ordered[0]
    for entry in ordered.dropFirst() where entry.score > top.score { top = entry }
    let label: StyleLabel = top.score >= 2 && f.games >= 2 ? top.label : .balanced
    return StyleClassification(label: label, scores: Dictionary(uniqueKeysWithValues: ordered.map { ($0.label, $0.score) }))
}

/// Elo update after a game vs the AI. `score` is 0, 0.5 or 1; `now` is TS `Date.now()` in ms.
public func updateRating(_ model: inout PlayerModel, aiElo: Int, score: Double, now: Int) {
    let expected = 1 / (1 + pow(10, Double(aiElo - model.rating) / 400))
    let k: Double = model.features.games < 10 ? 48 : 24
    model.rating = jsRound(max(200, Double(model.rating) + k * (score - expected)))
    model.ratingHistory.append(RatingPoint(t: now, rating: model.rating))
    if model.ratingHistory.count > 200 { model.ratingHistory.removeFirst() }
}

/// Merge one finished game (vs AI or not) into the model. TS `opts: { vsAi, aiElo? }` → `vsAI` / `aiElo`
/// (the rating only updates when `vsAI` and `aiElo` is present and non-zero, like the TS truthiness test).
@discardableResult
public func updateModelAfterGame(
    _ model: inout PlayerModel, game: Game, playerColor: PieceColor, analysis: [AnalyzedMove]?,
    vsAI: Bool, aiElo: Int? = nil, now: Int
) -> GameFacts {
    let facts = extractFacts(game, playerColor: playerColor)
    model.features.games += 1
    let games = model.features.games
    model.features.avgCaptureRate = roll(model.features.avgCaptureRate, facts.captureRate, games)
    model.features.avgEarlyQueenPly = roll(model.features.avgEarlyQueenPly, Double(facts.earlyQueenPly), games)
    model.features.avgCastlePly = roll(model.features.avgCastlePly, Double(facts.castlePly), games)
    model.features.avgChecksPerGame = roll(model.features.avgChecksPerGame, Double(facts.checks), games)
    model.features.avgPawnStorm = roll(model.features.avgPawnStorm, Double(facts.pawnStorm), games)
    model.features.avgTradeRate = roll(model.features.avgTradeRate, facts.tradeRate, games)
    if facts.avgThinkMs != 0 {
        // TS `f.avgThinkMs || facts.avgThinkMs`
        let prev = model.features.avgThinkMs != 0 ? model.features.avgThinkMs : facts.avgThinkMs
        model.features.avgThinkMs = roll(prev, facts.avgThinkMs, games)
    }

    if let analysis {
        let startTurn = game.positionAt(0).turn
        let playerMoves = analysis.enumerated()
            .filter { ($0.offset % 2 == 0 ? startTurn : startTurn.opponent) == playerColor }
            .map(\.element)
        if !playerMoves.isEmpty {
            let cpLoss = Double(playerMoves.reduce(0) { $0 + $1.cpLoss }) / Double(playerMoves.count)
            let prev = model.features.avgCpLoss != 0 ? model.features.avgCpLoss : cpLoss
            model.features.avgCpLoss = roll(prev, cpLoss, games)
        }
        for (k, v) in extractWeaknesses(game, playerColor: playerColor, analysis: analysis) {
            model.weaknesses[k] += v
        }
    }

    let playerWon = won(game, playerColor: playerColor)
    if let openingName = facts.openingName {
        var index = model.openings.firstIndex { $0.name == openingName }
        if index == nil {
            model.openings.append(OpeningStat(name: openingName, count: 0, asWhite: 0, wins: 0))
            index = model.openings.count - 1
        }
        if let i = index {
            model.openings[i].count += 1
            if playerColor == .white { model.openings[i].asWhite += 1 }
            if playerWon { model.openings[i].wins += 1 }
        }
        // `sort((a, b) => b.count - a.count)` is stable.
        model.openings = model.openings.enumerated()
            .sorted { a, b in a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset }
            .map(\.element)
        if model.openings.count > 12 { model.openings.removeLast(model.openings.count - 12) }
    }

    let playerDrew = drew(game)
    if playerWon {
        model.wins += 1
        model.streak = max(1, model.streak + 1)
    } else if playerDrew {
        model.draws += 1
        model.streak = 0
    } else {
        model.losses += 1
        model.streak = min(-1, model.streak - 1)
    }

    if vsAI, let aiElo, aiElo != 0 {
        updateRating(&model, aiElo: aiElo, score: playerWon ? 1 : playerDrew ? 0.5 : 0, now: now)
    }
    return facts
}

/// Top weaknesses sorted by count (for insights + challenge generation).
public func topWeaknesses(_ model: PlayerModel, n: Int = 3) -> [WeaknessCount] {
    // `Object.entries(...).filter(...).sort((a, b) => b[1] - a[1])`: the stable sort keeps key order on ties.
    Array(
        model.weaknesses.entries
            .filter { $0.count > 0 }
            .enumerated()
            .sorted { a, b in a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset }
            .map(\.element)
            .prefix(n)
    )
}
