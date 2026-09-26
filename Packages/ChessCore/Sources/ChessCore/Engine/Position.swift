// Ported 1:1 from src/engine/position.ts.
//
// TypeScript name → Swift name
//   START_FEN                       → Position.startFEN
//   new Position(fen) / loadFen     → Position(fen:) / load(fen:)   (throw FENError like the TS `throw new Error`)
//   toFen                           → fen
//   computeHash / hashLo / hashHi   → recomputeHash() / hashLo / hashHi (packed in `hash`)
//   hashKey                         → hashKey
//   attacked / inCheck              → isAttacked(_:by:) / isInCheck(_:)
//   generatePseudo(out)             → generatePseudoLegalMoves(into:) / generatePseudoLegalMoves()
//   generateLegal / legalMovesFrom  → generateLegalMoves() / legalMoves(from:)
//   hasLegalMoves                   → hasLegalMoves
//   makeMove / unmakeMove / clone   → makeMove(_:) / unmakeMove() / clone()
//   ep / kingSq[c]                  → enPassant / kingSquare(_:)
//   materialOf                      → material(of:)
//   hasMatingPotential              → hasMatingPotential(_:)
//   isInsufficientMaterial          → isInsufficientMaterial
//   isDeadPosition                  → isDeadPosition

/// TS `throw new Error('Invalid FEN: …')` / `'Invalid FEN piece: …'`.
public enum FENError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidFEN(String)
    case invalidPiece(Character)

    public var description: String {
        switch self {
        case .invalidFEN(let fen): return "Invalid FEN: \(fen)"
        case .invalidPiece(let ch): return "Invalid FEN piece: \(ch)"
        }
    }
}

/// TS `interface Undo`.
struct Undo: Sendable {
    var move: Move
    /// Signed piece (the EP-captured pawn for EP moves).
    var captured: Piece
    var castling: CastlingRights
    var enPassant: Int
    var halfmove: Int
    var hash: UInt64
}

private let pawnCaptureFileDeltas = [-1, 1]

public struct Position: Sendable {
    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// Which castling rights survive a piece moving from/to each square (TS `CASTLE_MASK`).
    private static let castleMask: [CastlingRights] = {
        var mask = [CastlingRights](repeating: .all, count: 64)
        mask[0] = CastlingRights.all.subtracting(.whiteQueenside)                          // a1
        mask[7] = CastlingRights.all.subtracting(.whiteKingside)                           // h1
        mask[4] = CastlingRights.all.subtracting([.whiteKingside, .whiteQueenside])        // e1
        mask[56] = CastlingRights.all.subtracting(.blackQueenside)                         // a8
        mask[63] = CastlingRights.all.subtracting(.blackKingside)                          // h8
        mask[60] = CastlingRights.all.subtracting([.blackKingside, .blackQueenside])       // e8
        return mask
    }()

    public private(set) var board = Board()
    public private(set) var turn: PieceColor = .white
    /// TS `castling`: CASTLE_* bitmask.
    public private(set) var castling: CastlingRights = []
    /// TS `ep`: en-passant target square (the skipped square), or -1.
    public private(set) var enPassant: Int = -1
    /// Plies since the last pawn move or capture (for the 50/75-move rules).
    public private(set) var halfmove = 0
    public private(set) var fullmove = 1
    /// TS `kingSq: [number, number]`.
    private var kingSquares: (white: Int, black: Int) = (4, 60)
    /// Packed Zobrist key: TS `hashHi << 32 | hashLo`.
    public private(set) var hash: UInt64 = 0
    private var undoStack: [Undo] = []

    /// The start position.
    public init() {
        do {
            try self.init(fen: Position.startFEN)
        } catch {
            preconditionFailure("the start FEN is valid: \(error)")
        }
    }

    /// TS `new Position(fen)`.
    public init(fen: String) throws {
        undoStack.reserveCapacity(64)
        try load(fen: fen)
    }

    // MARK: - Hash halves and king squares

    /// TS `hashLo`.
    @inline(__always) public var hashLo: UInt32 { Zobrist.lo(of: hash) }
    /// TS `hashHi`.
    @inline(__always) public var hashHi: UInt32 { Zobrist.hi(of: hash) }

    /// TS `kingSq[color]`.
    @inline(__always) public func kingSquare(_ color: PieceColor) -> Int {
        color == .white ? kingSquares.white : kingSquares.black
    }

    @inline(__always) private mutating func setKingSquare(_ color: PieceColor, _ sq: Int) {
        if color == .white { kingSquares.white = sq } else { kingSquares.black = sq }
    }

    // MARK: - FEN

    /// TS `loadFen(fen)`. Also clears the undo history.
    public mutating func load(fen: String) throws {
        let parts = fen.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 4 else { throw FENError.invalidFEN(fen) }
        board.clear()
        undoStack.removeAll(keepingCapacity: true)
        var sq = 56 // FEN starts at a8
        for ch in parts[0] {
            if ch == "/" { sq -= 16; continue }
            if let ascii = ch.asciiValue, ascii >= 49, ascii <= 56 { sq += Int(ascii) - 48; continue } // '1'…'8'
            guard let piece = Piece(fenCharacter: ch) else { throw FENError.invalidPiece(ch) }
            // The TS silently drops writes outside the Int8Array; here an overfull rank is rejected.
            guard sq >= 0, sq < 64 else { throw FENError.invalidFEN(fen) }
            board[sq] = piece
            if piece.type == .king { setKingSquare(piece.color, sq) }
            sq += 1
        }
        turn = parts[1] == "w" ? .white : .black
        castling = []
        if parts[2].contains("K") { castling.insert(.whiteKingside) }
        if parts[2].contains("Q") { castling.insert(.whiteQueenside) }
        if parts[2].contains("k") { castling.insert(.blackKingside) }
        if parts[2].contains("q") { castling.insert(.blackQueenside) }
        enPassant = parts[3] == "-" ? -1 : (parseSquare(parts[3]) ?? -1)
        halfmove = parts.count > 4 ? (parseIntPrefix(parts[4]) ?? 0) : 0             // TS `parseInt(...) || 0`
        let full = parts.count > 5 ? (parseIntPrefix(parts[5]) ?? 0) : 0
        fullmove = full == 0 ? 1 : full                                             // TS `parseInt(...) || 1`
        recomputeHash()
    }

    /// TS `toFen()`.
    public var fen: String {
        var out = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty = 0
            for file in 0..<8 {
                let p = board[squareAt(file: file, rank: rank)]
                if p.isEmpty { empty += 1; continue }
                if empty > 0 { out += String(empty); empty = 0 }
                out.append(p.fenCharacter)
            }
            if empty > 0 { out += String(empty) }
            if rank > 0 { out += "/" }
        }
        var castle = ""
        if castling.contains(.whiteKingside) { castle += "K" }
        if castling.contains(.whiteQueenside) { castle += "Q" }
        if castling.contains(.blackKingside) { castle += "k" }
        if castling.contains(.blackQueenside) { castle += "q" }
        return [
            out,
            turn == .white ? "w" : "b",
            castle.isEmpty ? "-" : castle,
            enPassant >= 0 ? squareName(enPassant) : "-",
            String(halfmove),
            String(fullmove),
        ].joined(separator: " ")
    }

    // MARK: - Hashing

    /// TS `computeHash()`: rebuilds the Zobrist key from scratch.
    public mutating func recomputeHash() {
        var h: UInt64 = 0
        for sq in 0..<64 {
            let p = board[sq]
            if p.isEmpty { continue }
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: p.type, color: p.color, square: sq)]
        }
        h ^= Zobrist.castling[Int(castling.rawValue)]
        if enPassant >= 0 { h ^= Zobrist.enPassant[fileOf(enPassant)] }
        if turn == .black { h ^= Zobrist.side }
        hash = h
    }

    /// Repetition key: position identity per FIDE (placement + turn + castling + ep rights).
    /// TS `hashLo.toString(36) + '.' + hashHi.toString(36)`.
    public var hashKey: String {
        String(hashLo, radix: 36) + "." + String(hashHi, radix: 36)
    }

    // MARK: - Attacks

    /// TS `attacked(sq, by)`: is `sq` attacked by any piece of colour `by`?
    public func isAttacked(_ sq: Int, by: PieceColor) -> Bool {
        let file = fileOf(sq)
        // Pawns: a white pawn on sq-7/sq-9 attacks sq (and mirrored for black).
        if by == .white {
            let pawn = Piece(type: .pawn, color: .white)
            if file > 0 && sq >= 9 && board[sq - 9] == pawn { return true }
            if file < 7 && sq >= 7 && board[sq - 7] == pawn { return true }
        } else {
            let pawn = Piece(type: .pawn, color: .black)
            if file > 0 && sq <= 56 && board[sq + 7] == pawn { return true }
            if file < 7 && sq <= 54 && board[sq + 9] == pawn { return true }
        }
        // Knights
        let knight = Piece(type: .knight, color: by)
        for (d, fd) in knightDeltas {
            let t = sq + d
            if t < 0 || t > 63 { continue }
            if fileOf(t) - file != fd { continue }
            if board[t] == knight { return true }
        }
        // King
        let king = Piece(type: .king, color: by)
        for (d, fd) in kingDeltas {
            let t = sq + d
            if t < 0 || t > 63 { continue }
            if fileOf(t) - file != fd { continue }
            if board[t] == king { return true }
        }
        // Sliders
        let bishop = Piece(type: .bishop, color: by)
        let rook = Piece(type: .rook, color: by)
        let queen = Piece(type: .queen, color: by)
        for (d, fd) in bishopDirections {
            var t = sq, prevFile = file
            while true {
                t += d
                if t < 0 || t > 63 { break }
                let f = fileOf(t)
                if f - prevFile != fd { break }
                prevFile = f
                let p = board[t]
                if !p.isEmpty {
                    if p == bishop || p == queen { return true }
                    break
                }
            }
        }
        for (d, fd) in rookDirections {
            var t = sq, prevFile = file
            while true {
                t += d
                if t < 0 || t > 63 { break }
                let f = fileOf(t)
                if f - prevFile != fd { break }
                prevFile = f
                let p = board[t]
                if !p.isEmpty {
                    if p == rook || p == queen { return true }
                    break
                }
            }
        }
        return false
    }

    /// TS `inCheck(color = this.turn)`.
    public func isInCheck(_ color: PieceColor? = nil) -> Bool {
        let c = color ?? turn
        return isAttacked(kingSquare(c), by: c.opponent)
    }

    // MARK: - Move generation

    /// TS `generatePseudo(out)`: appends the pseudo-legal moves for the side to move, in the TS order
    /// (castling is pre-validated for attacks).
    public func generatePseudoLegalMoves(into out: inout MoveList) {
        let us = turn
        let them = us.opponent
        let forward = us == .white ? 8 : -8
        let startRank = us == .white ? 1 : 6
        let promoRank = us == .white ? 7 : 0

        for from in 0..<64 {
            let p = board[from]
            if p.isEmpty || p.color != us { continue }
            let type = p.type
            let file = fileOf(from)

            if type == .pawn {
                let one = from + forward
                if one >= 0 && one <= 63 && board[one].isEmpty {
                    if rankOf(one) == promoRank {
                        out.append(Move(from: from, to: one, promotion: .queen))
                        out.append(Move(from: from, to: one, promotion: .rook))
                        out.append(Move(from: from, to: one, promotion: .bishop))
                        out.append(Move(from: from, to: one, promotion: .knight))
                    } else {
                        out.append(Move(from: from, to: one))
                        if rankOf(from) == startRank {
                            let two = from + 2 * forward
                            if board[two].isEmpty { out.append(Move(from: from, to: two, flags: .doublePush)) }
                        }
                    }
                }
                for df in pawnCaptureFileDeltas {
                    if file + df < 0 || file + df > 7 { continue }
                    let to = from + forward + df
                    if to < 0 || to > 63 { continue }
                    let target = board[to]
                    if !target.isEmpty && target.color == them {
                        if rankOf(to) == promoRank {
                            out.append(Move(from: from, to: to, promotion: .queen))
                            out.append(Move(from: from, to: to, promotion: .rook))
                            out.append(Move(from: from, to: to, promotion: .bishop))
                            out.append(Move(from: from, to: to, promotion: .knight))
                        } else {
                            out.append(Move(from: from, to: to))
                        }
                    } else if to == enPassant {
                        out.append(Move(from: from, to: to, flags: .enPassant))
                    }
                }
            } else if type == .knight {
                for (d, fd) in knightDeltas {
                    let to = from + d
                    if to < 0 || to > 63 { continue }
                    if fileOf(to) - file != fd { continue }
                    let target = board[to]
                    if target.isEmpty || target.color == them { out.append(Move(from: from, to: to)) }
                }
            } else if type == .king {
                for (d, fd) in kingDeltas {
                    let to = from + d
                    if to < 0 || to > 63 { continue }
                    if fileOf(to) - file != fd { continue }
                    let target = board[to]
                    if target.isEmpty || target.color == them { out.append(Move(from: from, to: to)) }
                }
                // Castling: rights valid, path empty, king not in/through check.
                if us == .white && from == 4 {
                    let rook = Piece(type: .rook, color: .white)
                    if castling.contains(.whiteKingside) && board[5].isEmpty && board[6].isEmpty && board[7] == rook
                        && !isAttacked(4, by: them) && !isAttacked(5, by: them) && !isAttacked(6, by: them) {
                        out.append(Move(from: 4, to: 6, flags: .castleKingside))
                    }
                    if castling.contains(.whiteQueenside) && board[3].isEmpty && board[2].isEmpty && board[1].isEmpty && board[0] == rook
                        && !isAttacked(4, by: them) && !isAttacked(3, by: them) && !isAttacked(2, by: them) {
                        out.append(Move(from: 4, to: 2, flags: .castleQueenside))
                    }
                } else if us == .black && from == 60 {
                    let rook = Piece(type: .rook, color: .black)
                    if castling.contains(.blackKingside) && board[61].isEmpty && board[62].isEmpty && board[63] == rook
                        && !isAttacked(60, by: them) && !isAttacked(61, by: them) && !isAttacked(62, by: them) {
                        out.append(Move(from: 60, to: 62, flags: .castleKingside))
                    }
                    if castling.contains(.blackQueenside) && board[59].isEmpty && board[58].isEmpty && board[57].isEmpty && board[56] == rook
                        && !isAttacked(60, by: them) && !isAttacked(59, by: them) && !isAttacked(58, by: them) {
                        out.append(Move(from: 60, to: 58, flags: .castleQueenside))
                    }
                }
            } else {
                // Bishop → diagonals, rook → files/ranks, anything else (the queen) → both, diagonals first.
                if type != .rook { appendSlides(from: from, file: file, along: bishopDirections, them: them, into: &out) }
                if type != .bishop { appendSlides(from: from, file: file, along: rookDirections, them: them, into: &out) }
            }
        }
    }

    @inline(__always)
    private func appendSlides(from: Int, file: Int, along directions: [(delta: Int, fileDelta: Int)],
                              them: PieceColor, into out: inout MoveList) {
        for (d, fd) in directions {
            var to = from, prevFile = file
            while true {
                to += d
                if to < 0 || to > 63 { break }
                let f = fileOf(to)
                if f - prevFile != fd { break }
                prevFile = f
                let target = board[to]
                if target.isEmpty { out.append(Move(from: from, to: to)); continue }
                if target.color == them { out.append(Move(from: from, to: to)) }
                break
            }
        }
    }

    /// TS `generatePseudo()` returning a fresh array.
    public func generatePseudoLegalMoves() -> [Move] {
        var list = MoveList()
        generatePseudoLegalMoves(into: &list)
        return Array(list)
    }

    /// TS `generateLegal()`: fully legal moves for the side to move, in generation order.
    /// Works on a scratch copy, so the receiver (and its undo history) is untouched.
    public func generateLegalMoves() -> [Move] {
        var pseudo = MoveList()
        generatePseudoLegalMoves(into: &pseudo)
        var scratch = clone()
        let us = turn
        let them = us.opponent
        var legal: [Move] = []
        legal.reserveCapacity(pseudo.count)
        for i in 0..<pseudo.count {
            let m = pseudo[i]
            scratch.makeMove(m)
            if !scratch.isAttacked(scratch.kingSquare(us), by: them) { legal.append(m) }
            scratch.unmakeMove()
        }
        return legal
    }

    /// TS `legalMovesFrom(from)`: legal moves originating from one square (for UI highlighting).
    public func legalMoves(from: Int) -> [Move] {
        generateLegalMoves().filter { $0.from == from }
    }

    /// TS `hasLegalMoves()`.
    public var hasLegalMoves: Bool {
        var pseudo = MoveList()
        generatePseudoLegalMoves(into: &pseudo)
        var scratch = clone()
        let us = turn
        let them = us.opponent
        for i in 0..<pseudo.count {
            scratch.makeMove(pseudo[i])
            let ok = !scratch.isAttacked(scratch.kingSquare(us), by: them)
            scratch.unmakeMove()
            if ok { return true }
        }
        return false
    }

    // MARK: - Make / unmake

    /// TS `makeMove(m)`: plays a pseudo-legal move and pushes an undo record.
    public mutating func makeMove(_ m: Move) {
        let from = m.from, to = m.to, flags = m.flags, promo = m.promotion
        let piece = board[from]
        let us = turn
        let them = us.opponent
        let type = piece.type

        var captured = board[to]
        var capturedSq = to
        if flags.contains(.enPassant) {
            capturedSq = to + (us == .white ? -8 : 8)
            captured = board[capturedSq]
        }

        undoStack.append(Undo(move: m, captured: captured, castling: castling, enPassant: enPassant,
                              halfmove: halfmove, hash: hash))

        var h = hash

        // Remove captured piece
        if !captured.isEmpty {
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: captured.type, color: them, square: capturedSq)]
            board[capturedSq] = .empty
        }

        // Move the piece (with promotion)
        h ^= Zobrist.pieces[Zobrist.pieceIndex(type: type, color: us, square: from)]
        let newType = promo == .empty ? type : promo
        h ^= Zobrist.pieces[Zobrist.pieceIndex(type: newType, color: us, square: to)]
        board[from] = .empty
        board[to] = Piece(type: newType, color: us)

        // Castling rook hop
        if flags.contains(.castleKingside) {
            let rFrom = us == .white ? 7 : 63, rTo = us == .white ? 5 : 61
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: .rook, color: us, square: rFrom)]
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: .rook, color: us, square: rTo)]
            board[rTo] = board[rFrom]
            board[rFrom] = .empty
        } else if flags.contains(.castleQueenside) {
            let rFrom = us == .white ? 0 : 56, rTo = us == .white ? 3 : 59
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: .rook, color: us, square: rFrom)]
            h ^= Zobrist.pieces[Zobrist.pieceIndex(type: .rook, color: us, square: rTo)]
            board[rTo] = board[rFrom]
            board[rFrom] = .empty
        }

        if type == .king { setKingSquare(us, to) }

        // Castling rights
        h ^= Zobrist.castling[Int(castling.rawValue)]
        castling = castling.intersection(Position.castleMask[from]).intersection(Position.castleMask[to])
        h ^= Zobrist.castling[Int(castling.rawValue)]

        // En passant target — only recorded when an enemy pawn stands ready to
        // capture, so repetition hashing matches FIDE position identity.
        if enPassant >= 0 { h ^= Zobrist.enPassant[fileOf(enPassant)] }
        enPassant = -1
        if flags.contains(.doublePush) {
            let enemyPawn = Piece(type: .pawn, color: them)
            let f = fileOf(to)
            if (f > 0 && board[to - 1] == enemyPawn) || (f < 7 && board[to + 1] == enemyPawn) {
                enPassant = (from + to) / 2
            }
        }
        if enPassant >= 0 { h ^= Zobrist.enPassant[fileOf(enPassant)] }

        // Clocks
        halfmove = (type == .pawn || !captured.isEmpty) ? 0 : halfmove + 1
        if us == .black { fullmove += 1 }

        // Side to move
        turn = them
        h ^= Zobrist.side

        hash = h
    }

    /// TS `unmakeMove()`: reverts the most recent `makeMove`.
    public mutating func unmakeMove() {
        guard let undo = undoStack.popLast() else { preconditionFailure("unmakeMove with empty stack") }
        let m = undo.move
        let from = m.from, to = m.to, flags = m.flags, promo = m.promotion
        let us = turn.opponent // side that made the move

        // Un-move piece (undo promotion)
        let piece = board[to]
        board[from] = promo == .empty ? piece : Piece(type: .pawn, color: us)
        board[to] = .empty

        // Restore captured piece
        if !undo.captured.isEmpty {
            let capturedSq = flags.contains(.enPassant) ? to + (us == .white ? -8 : 8) : to
            board[capturedSq] = undo.captured
        }

        // Undo castling rook hop
        if flags.contains(.castleKingside) {
            let rFrom = us == .white ? 7 : 63, rTo = us == .white ? 5 : 61
            board[rFrom] = board[rTo]
            board[rTo] = .empty
        } else if flags.contains(.castleQueenside) {
            let rFrom = us == .white ? 0 : 56, rTo = us == .white ? 3 : 59
            board[rFrom] = board[rTo]
            board[rTo] = .empty
        }

        if board[from].type == .king { setKingSquare(us, from) }

        turn = us
        if us == .black { fullmove -= 1 }
        castling = undo.castling
        enPassant = undo.enPassant
        halfmove = undo.halfmove
        hash = undo.hash
    }

    /// TS `clone()`: a copy that does NOT carry the undo history.
    public func clone() -> Position {
        var copy = self
        copy.undoStack = []
        return copy
    }

    // MARK: - Material

    /// TS `materialOf(color)`: signed pieces of one colour, excluding the king, in square order.
    public func material(of color: PieceColor) -> [Piece] {
        var out: [Piece] = []
        for sq in 0..<64 {
            let p = board[sq]
            if !p.isEmpty && p.color == color && p.type != .king { out.append(p) }
        }
        return out
    }

    /// Can `color` possibly deliver checkmate by ANY sequence of legal moves
    /// (helpmates included)? Used for the timeout rule and dead-position checks.
    public func hasMatingPotential(_ color: PieceColor) -> Bool {
        var knights = 0, bishopsLight = 0, bishopsDark = 0, heavy = 0, pawns = 0
        var oppPieces = 0, oppBishopsLight = 0, oppBishopsDark = 0 // TS also counts oppKnights but never reads it
        for sq in 0..<64 {
            let p = board[sq]
            if p.isEmpty { continue }
            let t = p.type
            if t == .king { continue }
            let dark = ((sq >> 3) + (sq & 7)) % 2 == 0
            if p.color == color {
                if t == .pawn { pawns += 1 }
                else if t == .knight { knights += 1 }
                else if t == .bishop { if dark { bishopsDark += 1 } else { bishopsLight += 1 } }
                else { heavy += 1 }
            } else {
                oppPieces += 1
                if t == .bishop { if dark { oppBishopsDark += 1 } else { oppBishopsLight += 1 } }
            }
        }
        let bishops = bishopsLight + bishopsDark
        if pawns > 0 || heavy > 0 { return true }
        if knights + bishops == 0 { return false }               // bare king
        if knights >= 2 { return true }                          // K+NN: mate constructible
        if knights + bishops >= 2 { return true }                // B+B or B+N
        // Single minor piece:
        if knights == 1 { return oppPieces > 0 }                 // K+N mates only with a helping blocker
        // Single bishop: needs an opposing piece that isn't a same-colored bishop
        let oppOther = oppPieces - (bishopsLight > 0 ? oppBishopsLight : oppBishopsDark)
        return oppOther > 0
    }

    /// FIDE insufficient-material draw (neither side can ever checkmate):
    /// K vs K, K+B vs K, K+N vs K, and any number of bishops all on one square
    /// color across BOTH sides (covers K+B vs K+B same-colored bishops).
    public var isInsufficientMaterial: Bool {
        var knights = 0, bishopsLight = 0, bishopsDark = 0, other = 0
        for sq in 0..<64 {
            let p = board[sq]
            if p.isEmpty { continue }
            let t = p.type
            if t == .king { continue }
            if t == .knight { knights += 1 }
            else if t == .bishop {
                if ((sq >> 3) + (sq & 7)) % 2 == 0 { bishopsDark += 1 } else { bishopsLight += 1 }
            } else { other += 1 }
        }
        if other > 0 { return false }
        let bishops = bishopsLight + bishopsDark
        if knights == 0 && bishops == 0 { return true }                                   // K vs K
        if knights == 1 && bishops == 0 { return true }                                   // K+N vs K
        if knights == 0 && (bishopsLight == 0 || bishopsDark == 0) { return true }        // bishops on one color only
        return false
    }

    /// Dead position: no sequence of legal moves can produce mate for either side.
    public var isDeadPosition: Bool {
        !hasMatingPotential(.white) && !hasMatingPotential(.black)
    }
}

/// JS `parseInt(text, 10)` as used for the FEN clocks: optional sign, then leading decimal digits;
/// trailing characters are ignored; nil when there are no digits (JS `NaN`).
func parseIntPrefix(_ text: Substring) -> Int? {
    var bytes = text.utf8[...]
    var negative = false
    if let first = bytes.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
        negative = first == UInt8(ascii: "-")
        bytes = bytes.dropFirst()
    }
    var value = 0
    var digits = 0
    for b in bytes {
        guard b >= 48, b <= 57, digits < 18 else { break }
        value = value * 10 + Int(b - 48)
        digits += 1
    }
    return digits == 0 ? nil : (negative ? -value : value)
}
