// The 64-square mailbox board (TS `board = new Int8Array(64)`), stored inline so that copying a
// Position copies 64 bytes and reading or writing a square never touches the heap.

public struct Board: Equatable, Sendable {
    typealias Storage = (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)

    /// 64 signed piece codes viewed as eight 64-bit words.
    var storage: Storage = (0, 0, 0, 0, 0, 0, 0, 0)

    public init() {}

    /// The piece on `square` (0 = a1 … 63 = h8).
    public subscript(square: Int) -> Piece {
        @inline(__always) get {
            assert(square >= 0 && square < 64, "square out of range")
            return withUnsafeBytes(of: storage) { bytes in
                Piece(code: bytes.load(fromByteOffset: square, as: Int8.self))
            }
        }
        @inline(__always) set {
            assert(square >= 0 && square < 64, "square out of range")
            withUnsafeMutableBytes(of: &storage) { bytes in
                bytes.storeBytes(of: newValue.code, toByteOffset: square, as: Int8.self)
            }
        }
    }

    /// TS `board.fill(EMPTY)`.
    public mutating func clear() {
        storage = (0, 0, 0, 0, 0, 0, 0, 0)
    }

    public static func == (lhs: Board, rhs: Board) -> Bool {
        lhs.storage.0 == rhs.storage.0 && lhs.storage.1 == rhs.storage.1
            && lhs.storage.2 == rhs.storage.2 && lhs.storage.3 == rhs.storage.3
            && lhs.storage.4 == rhs.storage.4 && lhs.storage.5 == rhs.storage.5
            && lhs.storage.6 == rhs.storage.6 && lhs.storage.7 == rhs.storage.7
    }
}
