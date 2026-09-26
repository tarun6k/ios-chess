// Ported 1:1 from src/ai/eval.ts.
//
// TypeScript name → Swift name
//   PIECE_VALUE                       → pieceValues
//   EvalParams / NEUTRAL_PARAMS       → EvalParams / EvalParams.neutral
//   PST_PAWN … PST_KING_EG            → PieceSquareTables.pawn … .kingEG (internal, diffed against the TS in EvalTests)
//   KNIGHT_MOVES_D / KNIGHT_MOVES_F   → PieceSquareTables.knightMovesD / .knightMovesF
//   evaluate(pos, params)             → evaluate(_:params:)
//
// The TS does its arithmetic in doubles and `Math.round`s once at the end; every term here is
// computed in the same order on Doubles so the rounded result is bit-for-bit the same.

/// Centipawn piece values indexed by `PieceType.rawValue` (TS `PIECE_VALUE`).
public let pieceValues: [Int] = [0, 100, 320, 330, 500, 900, 20000]

/// Adaptation knobs — how the player model bends the AI's judgement.
/// All default to neutral; see src/ai/adaptation.ts for how they are set.
public struct EvalParams: Hashable, Sendable, Codable {
    /// >0: value attacking play near the enemy king more (vs passive players).
    public var aggression: Double
    /// >0: value space and advanced pawns more (squeeze passive players).
    public var spaceWeight: Double
    /// >0: value own king safety more (punish aggressive players' attacks).
    public var kingSafetyWeight: Double
    /// >0: bonus for keeping the center pawn-locked (frustrate tacticians).
    public var closedPref: Double
    /// scale on mobility term.
    public var mobilityWeight: Double

    public init(aggression: Double = 0, spaceWeight: Double = 0, kingSafetyWeight: Double = 0,
                closedPref: Double = 0, mobilityWeight: Double = 1) {
        self.aggression = aggression
        self.spaceWeight = spaceWeight
        self.kingSafetyWeight = kingSafetyWeight
        self.closedPref = closedPref
        self.mobilityWeight = mobilityWeight
    }

    /// TS `NEUTRAL_PARAMS`.
    public static let neutral = EvalParams()
}

// Piece-square tables (Michniewski's simplified eval), written rank-8 row first.
// White reads table[sq ^ 56], black reads table[sq].
enum PieceSquareTables {
    static let pawn: [Int] = [
         0,  0,  0,  0,  0,  0,  0,  0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
         5,  5, 10, 25, 25, 10,  5,  5,
         0,  0,  0, 20, 20,  0,  0,  0,
         5, -5,-10,  0,  0,-10, -5,  5,
         5, 10, 10,-20,-20, 10, 10,  5,
         0,  0,  0,  0,  0,  0,  0,  0,
    ]
    static let knight: [Int] = [
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50,
    ]
    static let bishop: [Int] = [
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  5,  0,  0,  0,  0,  5,-10,
        -20,-10,-10,-10,-10,-10,-10,-20,
    ]
    static let rook: [Int] = [
         0,  0,  0,  0,  0,  0,  0,  0,
         5, 10, 10, 10, 10, 10, 10,  5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
         0,  0,  0,  5,  5,  0,  0,  0,
    ]
    static let queen: [Int] = [
        -20,-10,-10, -5, -5,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5,  5,  5,  5,  0,-10,
         -5,  0,  5,  5,  5,  5,  0, -5,
          0,  0,  5,  5,  5,  5,  0, -5,
        -10,  5,  5,  5,  5,  5,  0,-10,
        -10,  0,  5,  0,  0,  0,  0,-10,
        -20,-10,-10, -5, -5,-10,-10,-20,
    ]
    static let kingMG: [Int] = [
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -10,-20,-20,-20,-20,-20,-20,-10,
         20, 20,  0,  0,  0,  0, 20, 20,
         20, 30, 10,  0,  0, 10, 30, 20,
    ]
    static let kingEG: [Int] = [
        -50,-40,-30,-20,-20,-30,-40,-50,
        -30,-20,-10,  0,  0,-10,-20,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-30,  0,  0,  0,  0,-30,-30,
        -50,-30,-30,-30,-30,-30,-50,-50,
    ]

    /// Passed-pawn bonus by relative rank (the inline table in `evaluate`), scaled by `1.4 - 0.4 * phase`.
    static let passedPawnBonus: [Int] = [0, 10, 15, 25, 40, 65, 100, 0]

    static let knightMovesD: [Int] = [17, 15, 10, 6, -6, -10, -15, -17]
    static let knightMovesF: [Int] = [1, -1, 2, -2, 2, -2, 1, -1]

    /// TS `PST[t][relSq]` for the non-king pieces.
    @inline(__always) static func value(_ type: PieceType, _ relSq: Int) -> Int {
        switch type {
        case .pawn: return pawn[relSq]
        case .knight: return knight[relSq]
        case .bishop: return bishop[relSq]
        case .rook: return rook[relSq]
        default: return queen[relSq]
        }
    }
}

/// Pawn counts per file for both sides (TS `pawnFiles: [number[], number[]]`), kept off the heap.
private struct PawnFiles {
    var white = SIMD8<Int32>(repeating: 0)
    var black = SIMD8<Int32>(repeating: 0)

    @inline(__always) subscript(side: Int, file: Int) -> Int32 {
        get { side == 0 ? white[file] : black[file] }
        set { if side == 0 { white[file] = newValue } else { black[file] = newValue } }
    }
}

/// JS `Math.round`: nearest integer, halves toward +∞ (`Math.round(-2.5) === -2`).
@inline(__always) func jsRound(_ x: Double) -> Int {
    let floor = x.rounded(.down)
    return Int(x - floor >= 0.5 ? floor + 1 : floor)
}

/// Static evaluation in centipawns from WHITE's point of view.
public func evaluate(_ pos: Position, params: EvalParams = .neutral) -> Int {
    let b = pos.board
    var score = 0.0
    let whitePawn = Piece(type: .pawn, color: .white)
    let blackPawn = Piece(type: .pawn, color: .black)

    // Pass 1: gather pawn files, material, phase
    var phaseMaterial = 0 // non-pawn material of both sides
    var pawnFiles = PawnFiles()
    var bishops = (white: 0, black: 0)
    for sq in 0..<64 {
        let p = b[sq]
        if p.isEmpty { continue }
        let t = p.type
        if t == .pawn { pawnFiles[p.code > 0 ? 0 : 1, fileOf(sq)] += 1 }
        else if t != .king { phaseMaterial += pieceValues[t.rawValue] }
        if t == .bishop { if p.code > 0 { bishops.white += 1 } else { bishops.black += 1 } }
    }
    // phase: 1 = full middlegame, 0 = bare endgame  (max non-pawn material = 2*(2*320+2*330+2*500+900) = 6200)
    let phase = min(1, Double(phaseMaterial) / 6200)

    for sq in 0..<64 {
        let p = b[sq]
        if p.isEmpty { continue }
        let t = p.type
        let white = p.code > 0
        let us = white ? 0 : 1
        let sign: Double = white ? 1 : -1
        let relSq = white ? (sq ^ 56) : sq
        var v = Double(pieceValues[t.rawValue])

        if t == .king {
            v += Double(PieceSquareTables.kingMG[relSq]) * phase + Double(PieceSquareTables.kingEG[relSq]) * (1 - phase)
            // Pawn shield in the middlegame
            if phase > 0.4 {
                let f = fileOf(sq)
                let ownPawn = white ? whitePawn : blackPawn
                var shield = 0
                for df in -1...1 {
                    let ff = f + df
                    if ff < 0 || ff > 7 { continue }
                    let s1 = sq + (white ? 8 : -8) + df
                    let s2 = sq + (white ? 16 : -16) + df
                    if s1 >= 0 && s1 < 64 && b[s1] == ownPawn { shield += 12 }
                    else if s2 >= 0 && s2 < 64 && b[s2] == ownPawn { shield += 6 }
                }
                v += Double(shield) * phase * (1 + params.kingSafetyWeight)
            }
        } else {
            v += Double(PieceSquareTables.value(t, relSq))
        }

        if t == .pawn {
            let f = fileOf(sq)
            let r = rankOf(sq)
            let relRank = white ? r : 7 - r
            // doubled
            if pawnFiles[us, f] > 1 { v -= 12 }
            // isolated
            let leftOk = f > 0 && pawnFiles[us, f - 1] > 0
            let rightOk = f < 7 && pawnFiles[us, f + 1] > 0
            if !leftOk && !rightOk { v -= 15 }
            // passed: no enemy pawns ahead on this or adjacent files
            var passed = true
            let them = us ^ 1
            let enemyPawn = white ? blackPawn : whitePawn
            for df in -1...1 {
                if !passed { break }
                let ff = f + df
                if ff < 0 || ff > 7 { continue }
                if pawnFiles[them, ff] > 0 {
                    // check actual squares ahead
                    var rr = white ? r + 1 : r - 1
                    while rr >= 0 && rr < 8 {
                        if b[rr * 8 + ff] == enemyPawn { passed = false; break }
                        rr += white ? 1 : -1
                    }
                }
            }
            if passed { v += Double(PieceSquareTables.passedPawnBonus[relRank]) * (1.4 - 0.4 * phase) }
            // space: pawns advanced past the middle
            if relRank >= 4 { v += params.spaceWeight * 6 * Double(relRank - 3) }
        }

        if t == .rook {
            let f = fileOf(sq)
            if pawnFiles[us, f] == 0 { v += pawnFiles[us ^ 1, f] == 0 ? 18 : 9 } // open / semi-open
            // closed-position preference: rooks matter less, so a "closedPref" AI
            // slightly discounts its opponent-facing open lines — handled globally below.
        }

        // Mobility for minors + rooks (pseudo-mobility, cheap)
        if params.mobilityWeight != 0 && (t == .knight || t == .bishop || t == .rook) {
            var mob = 0
            let file = fileOf(sq)
            if t == .knight {
                for i in 0..<8 {
                    let to = sq + PieceSquareTables.knightMovesD[i]
                    if to < 0 || to > 63 { continue }
                    if fileOf(to) - file != PieceSquareTables.knightMovesF[i] { continue }
                    let q = b[to]
                    if q.isEmpty || (q.code > 0) != white { mob += 1 }
                }
            } else {
                // TS dirs/fds pairs: bishop [9, 7, -7, -9] / [1, -1, 1, -1], rook [8, -8, 1, -1] / [0, 0, 1, -1]
                let dirs = t == .bishop ? bishopDirections : rookDirections
                for (d, fd) in dirs {
                    var to = sq, prevF = file
                    while true {
                        to += d
                        if to < 0 || to > 63 { break }
                        let f2 = fileOf(to)
                        if f2 - prevF != fd { break }
                        prevF = f2
                        let q = b[to]
                        if q.isEmpty { mob += 1; continue }
                        if (q.code > 0) != white { mob += 1 }
                        break
                    }
                }
            }
            v += Double(mob * 2) * params.mobilityWeight
        }

        // Aggression: pieces near the enemy king are worth a bit more
        if params.aggression != 0 && t != .king && t != .pawn {
            let ek = pos.kingSquare(white ? .black : .white)
            let dist = max(abs(fileOf(sq) - fileOf(ek)), abs(rankOf(sq) - rankOf(ek)))
            if dist <= 3 { v += params.aggression * Double(4 - dist) * 6 }
        }

        score += sign * v
        // (the TS also keeps a `mg` accumulator that is only ever incremented by 0)
    }

    // Bishop pair
    if bishops.white >= 2 { score += 30 }
    if bishops.black >= 2 { score -= 30 }

    // Closed-center preference: count locked central pawn pairs (pawn faces enemy pawn).
    if params.closedPref != 0 {
        var locked = 0
        for f in 2...5 {
            for r in 2...5 {
                let sq = r * 8 + f
                if b[sq] == whitePawn && b[sq + 8] == blackPawn { locked += 1 }
            }
        }
        // Symmetric bonus scaled toward the side that wants it closed; applied
        // as a white-positive term times the side preference set by the caller.
        score += params.closedPref * Double(locked) * 8
    }

    return jsRound(score)
}
