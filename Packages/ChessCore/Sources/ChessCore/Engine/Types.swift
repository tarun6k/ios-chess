// Core engine types and constants, ported 1:1 from src/engine/types.ts.
// Square 0 = a1, 7 = h1, 56 = a8, 63 = h8.
//
// TypeScript name → Swift name
//   WHITE / BLACK, Color                 → PieceColor.white / .black (raw 0 / 1)
//   PAWN … KING                          → PieceType.pawn … .king (raw 1 … 6)
//   EMPTY, signed piece codes            → Piece.empty, Piece.code
//   colorOf / typeOf / makePiece         → Piece.color / Piece.type / Piece(type:color:)
//   fileOf / rankOf / square             → fileOf(_:) / rankOf(_:) / squareAt(file:rank:)
//   sqName / parseSquare                 → squareName(_:) / parseSquare(_:)
//   CASTLE_WK / WQ / BK / BQ             → CastlingRights.whiteKingside / …
//   FLAG_EP / DOUBLE / CASTLE_K / Q      → MoveFlags.enPassant / .doublePush / .castleKingside / .castleQueenside
//   makeMove / moveFrom / moveTo /
//   moveFlags / movePromo / moveToUci    → Move(from:to:flags:promotion:) / .from / .to / .flags / .promotion / .uci
//   PIECE_CHARS                          → PieceType.symbol, Piece.fenCharacter
//   KNIGHT_DELTAS / KING_DELTAS /
//   BISHOP_DIRS / ROOK_DIRS              → knightDeltas / kingDeltas / bishopDirections / rookDirections

/// Side colour. Raw values match the TypeScript `WHITE = 0`, `BLACK = 1` and the saved-data shape.
public enum PieceColor: Int, Hashable, Sendable, Codable, CaseIterable {
    case white = 0
    case black = 1

    /// TS `(color ^ 1) as Color`.
    @inline(__always) public var opponent: PieceColor { self == .white ? .black : .white }
}

/// Piece kind. Raw values match the TypeScript constants; `.empty` (0) is "no piece".
public struct PieceType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: Int

    @inline(__always) public init(rawValue: Int) { self.rawValue = rawValue }

    /// No piece, and "no promotion" inside a packed move. TS `0`.
    public static let empty = PieceType(rawValue: 0)
    public static let pawn = PieceType(rawValue: 1)
    public static let knight = PieceType(rawValue: 2)
    public static let bishop = PieceType(rawValue: 3)
    public static let rook = PieceType(rawValue: 4)
    public static let queen = PieceType(rawValue: 5)
    public static let king = PieceType(rawValue: 6)

    /// TS `PIECE_CHARS[type]` with `PIECE_CHARS = ' PNBRQK'`.
    public var symbol: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        default: return " "
        }
    }

    /// Inverse of `symbol` for the six uppercase piece letters (TS `PIECE_CHARS.indexOf(ch) > 0`).
    public init?(symbol: Character) {
        switch symbol {
        case "P": self = .pawn
        case "N": self = .knight
        case "B": self = .bishop
        case "R": self = .rook
        case "Q": self = .queen
        case "K": self = .king
        default: return nil
        }
    }
}

/// A board occupant: signed code, positive = white, negative = black, 0 = empty (TS `Int8Array` values).
public struct Piece: Hashable, Sendable {
    public var code: Int8

    @inline(__always) public init(code: Int8) { self.code = code }

    /// TS `makePiece(type, color)`.
    @inline(__always) public init(type: PieceType, color: PieceColor) {
        let t = Int8(truncatingIfNeeded: type.rawValue)
        code = color == .white ? t : -t
    }

    public static let empty = Piece(code: 0)

    @inline(__always) public var isEmpty: Bool { code == 0 }

    /// TS `colorOf`: positive codes are white; zero and negative codes report black.
    @inline(__always) public var color: PieceColor { code > 0 ? .white : .black }

    /// TS `typeOf`: the unsigned kind, `.empty` for an empty square.
    @inline(__always) public var type: PieceType { PieceType(rawValue: Int(code.magnitude)) }

    /// FEN letter: uppercase for white, lowercase for black, " " when empty.
    public var fenCharacter: Character {
        let upper = type.symbol
        return code > 0 ? upper : Character(upper.lowercased())
    }

    /// TS FEN piece parsing: `PIECE_CHARS.indexOf(ch.toUpperCase())` with white iff `ch === ch.toUpperCase()`.
    public init?(fenCharacter ch: Character) {
        let upper = ch.uppercased()
        guard upper.count == 1, let first = upper.first, let type = PieceType(symbol: first) else { return nil }
        self.init(type: type, color: String(ch) == upper ? .white : .black)
    }
}

// MARK: - Squares

/// TS `fileOf(sq)`: 0 = a … 7 = h.
@inline(__always) public func fileOf(_ sq: Int) -> Int { sq & 7 }

/// TS `rankOf(sq)`: 0 = rank 1 … 7 = rank 8.
@inline(__always) public func rankOf(_ sq: Int) -> Int { sq >> 3 }

/// TS `square(file, rank)`.
@inline(__always) public func squareAt(file: Int, rank: Int) -> Int { rank * 8 + file }

private let fileLetters: [Character] = ["a", "b", "c", "d", "e", "f", "g", "h"]

/// TS `sqName(sq)`: "a1" … "h8".
public func squareName(_ sq: Int) -> String {
    String(fileLetters[sq & 7]) + String((sq >> 3) + 1)
}

/// TS `parseSquare(name)`: reads the first two characters ("e4" → 28).
/// Returns nil when they are not a file a–h followed by a rank 1–8 (the TS returns an off-board number instead).
public func parseSquare(_ name: some StringProtocol) -> Int? {
    var it = name.utf8.makeIterator()
    guard let f = it.next(), let r = it.next() else { return nil }
    let file = Int(f) - 97, rank = Int(r) - 49
    guard file >= 0, file <= 7, rank >= 0, rank <= 7 else { return nil }
    return file + rank * 8
}

// MARK: - Castling rights

/// TS `CASTLE_*` bitmask.
public struct CastlingRights: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    @inline(__always) public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)   // CASTLE_WK
    public static let whiteQueenside = CastlingRights(rawValue: 2)  // CASTLE_WQ
    public static let blackKingside = CastlingRights(rawValue: 4)   // CASTLE_BK
    public static let blackQueenside = CastlingRights(rawValue: 8)  // CASTLE_BQ
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]
}

// MARK: - Moves

/// TS `FLAG_*` bits stored in bits 12–15 of a packed move.
public struct MoveFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    @inline(__always) public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let enPassant = MoveFlags(rawValue: 1)        // FLAG_EP
    public static let doublePush = MoveFlags(rawValue: 2)       // FLAG_DOUBLE
    public static let castleKingside = MoveFlags(rawValue: 4)   // FLAG_CASTLE_K
    public static let castleQueenside = MoveFlags(rawValue: 8)  // FLAG_CASTLE_Q
}

/// Packed 32-bit move, bit-identical to the TypeScript layout:
/// bits 0–5 from, 6–11 to, 12–15 flags, 16–18 promotion type (0 or N/B/R/Q).
public struct Move: Hashable, Sendable, CustomStringConvertible {
    public var raw: UInt32

    @inline(__always) public init(raw: UInt32) { self.raw = raw }

    /// TS `makeMove(from, to, flags = 0, promo = 0)`.
    @inline(__always) public init(from: Int, to: Int, flags: MoveFlags = [], promotion: PieceType = .empty) {
        raw = UInt32(truncatingIfNeeded: from)
            | UInt32(truncatingIfNeeded: to) << 6
            | UInt32(flags.rawValue) << 12
            | UInt32(truncatingIfNeeded: promotion.rawValue) << 16
    }

    /// TS `moveFrom(m)`: `m & 63`.
    @inline(__always) public var from: Int { Int(raw & 63) }
    /// TS `moveTo(m)`: `(m >> 6) & 63`.
    @inline(__always) public var to: Int { Int((raw >> 6) & 63) }
    /// TS `moveFlags(m)`: `(m >> 12) & 15`.
    @inline(__always) public var flags: MoveFlags { MoveFlags(rawValue: UInt8(truncatingIfNeeded: (raw >> 12) & 15)) }
    /// TS `movePromo(m)`: `(m >> 16) & 7`, `.empty` when the move is not a promotion.
    @inline(__always) public var promotion: PieceType { PieceType(rawValue: Int((raw >> 16) & 7)) }

    /// TS `moveToUci(m)`: long algebraic such as "e2e4" or "e7e8q".
    public var uci: String {
        let promo = promotion
        return squareName(from) + squareName(to) + (promo == .empty ? "" : promo.symbol.lowercased())
    }

    public var description: String { uci }
}

// MARK: - Step tables

/// TS `KNIGHT_DELTAS`: (square delta, file delta) pairs, in the TS order.
public let knightDeltas: [(delta: Int, fileDelta: Int)] = [
    (17, 1), (15, -1), (10, 2), (6, -2), (-6, 2), (-10, -2), (-15, 1), (-17, -1),
]
/// TS `KING_DELTAS`.
public let kingDeltas: [(delta: Int, fileDelta: Int)] = [
    (8, 0), (-8, 0), (1, 1), (-1, -1), (9, 1), (7, -1), (-7, 1), (-9, -1),
]
/// TS `BISHOP_DIRS`.
public let bishopDirections: [(delta: Int, fileDelta: Int)] = [
    (9, 1), (7, -1), (-7, 1), (-9, -1),
]
/// TS `ROOK_DIRS`.
public let rookDirections: [(delta: Int, fileDelta: Int)] = [
    (8, 0), (-8, 0), (1, 1), (-1, -1),
]
