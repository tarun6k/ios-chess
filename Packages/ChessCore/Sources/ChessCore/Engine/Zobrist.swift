// Zobrist hashing, ported from src/engine/zobrist.ts.
//
// The TypeScript keeps two independent 32-bit keys (`lo`, `hi`) because JS has no fast 64-bit
// integers. Here each key pair is packed into one UInt64 as `hi << 32 | lo`; XOR-ing packed keys is
// identical to XOR-ing the halves separately, so `Position.hashLo` / `hashHi` reproduce the TS values.

/// mulberry32, bit-identical to the TS implementation (32-bit wrapping arithmetic, logical shifts).
struct Mulberry32 {
    var state: UInt32

    init(seed: UInt32) { state = seed }

    mutating func next() -> UInt32 {
        state = state &+ 0x6d2b_79f5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return t ^ (t >> 14)
    }
}

public enum Zobrist {
    /// Seed shared with `zobrist.ts` (`mulberry32(0x9e3779b9)`).
    static let seed: UInt32 = 0x9e37_79b9

    /// Piece keys: index `pieceIndex(type:color:square:)`, 12 × 64 entries (TS `ZOBRIST_PIECES_LO/HI`).
    public static let pieces: [UInt64] = tables.pieces
    /// Castling-rights keys indexed by the 4-bit rights mask (TS `ZOBRIST_CASTLE_LO/HI`).
    public static let castling: [UInt64] = tables.castling
    /// En-passant keys indexed by file (TS `ZOBRIST_EP_LO/HI`).
    public static let enPassant: [UInt64] = tables.enPassant
    /// Side-to-move key, XOR-ed in when Black is to move (TS `ZOBRIST_SIDE_LO/HI`).
    public static let side: UInt64 = tables.side

    /// TS `pieceZobristIndex(type, color, sq)`: `((type - 1) + color * 6) * 64 + sq`.
    @inline(__always) public static func pieceIndex(type: PieceType, color: PieceColor, square: Int) -> Int {
        ((type.rawValue - 1) + color.rawValue * 6) * 64 + square
    }

    /// Packs a TS key pair into one 64-bit key.
    @inline(__always) static func key(lo: UInt32, hi: UInt32) -> UInt64 {
        UInt64(hi) << 32 | UInt64(lo)
    }

    /// The TS `lo` half of a packed key.
    @inline(__always) public static func lo(of key: UInt64) -> UInt32 { UInt32(truncatingIfNeeded: key) }
    /// The TS `hi` half of a packed key.
    @inline(__always) public static func hi(of key: UInt64) -> UInt32 { UInt32(truncatingIfNeeded: key >> 32) }

    /// Inverse of `Position.hashKey` (`lo.toString(36) + '.' + hi.toString(36)`); nil for any other string.
    public static func hash(fromKey key: String) -> UInt64? {
        guard let dot = key.firstIndex(of: "."),
              let lo = UInt32(key[..<dot], radix: 36),
              let hi = UInt32(key[key.index(after: dot)...], radix: 36) else { return nil }
        return Zobrist.key(lo: lo, hi: hi)
    }

    private struct Tables {
        var pieces: [UInt64] = []
        var castling: [UInt64] = []
        var enPassant: [UInt64] = []
        var side: UInt64 = 0

        /// Draws from a single RNG stream in exactly the TS order: pieces (lo, hi per index),
        /// then castling, then en passant, then the side key.
        init() {
            var rng = Mulberry32(seed: Zobrist.seed)
            pieces.reserveCapacity(12 * 64)
            for _ in 0..<(12 * 64) {
                let lo = rng.next(), hi = rng.next()
                pieces.append(Zobrist.key(lo: lo, hi: hi))
            }
            castling.reserveCapacity(16)
            for _ in 0..<16 {
                let lo = rng.next(), hi = rng.next()
                castling.append(Zobrist.key(lo: lo, hi: hi))
            }
            enPassant.reserveCapacity(8)
            for _ in 0..<8 {
                let lo = rng.next(), hi = rng.next()
                enPassant.append(Zobrist.key(lo: lo, hi: hi))
            }
            let sideLo = rng.next(), sideHi = rng.next()
            side = Zobrist.key(lo: sideLo, hi: sideHi)
        }
    }

    private static let tables = Tables()
}
