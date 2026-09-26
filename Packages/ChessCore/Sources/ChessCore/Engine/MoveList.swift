// A fixed-capacity, stack-allocated move buffer for the generation / search hot paths, replacing the
// TS pattern of pushing into a fresh JS array per node. 256 slots cover any pseudo-legal move set.

public struct MoveList: Sendable {
    public static let capacity = 256

    typealias Chunk = (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) // 16 moves
    typealias Storage = (
        Chunk, Chunk, Chunk, Chunk, Chunk, Chunk, Chunk, Chunk,
        Chunk, Chunk, Chunk, Chunk, Chunk, Chunk, Chunk, Chunk
    )

    var storage: Storage
    public private(set) var count: Int = 0

    public init() {
        let z: Chunk = (0, 0, 0, 0, 0, 0, 0, 0)
        storage = (z, z, z, z, z, z, z, z, z, z, z, z, z, z, z, z)
    }

    @inline(__always) public var isEmpty: Bool { count == 0 }

    /// TS `out.push(move)`.
    @inline(__always) public mutating func append(_ move: Move) {
        precondition(count < MoveList.capacity, "MoveList overflow")
        withUnsafeMutableBytes(of: &storage) { bytes in
            bytes.storeBytes(of: move.raw, toByteOffset: count &* 4, as: UInt32.self)
        }
        count &+= 1
    }

    /// TS `out.length = 0`.
    @inline(__always) public mutating func removeAll() { count = 0 }

    public subscript(index: Int) -> Move {
        @inline(__always) get {
            assert(index >= 0 && index < count, "MoveList index out of range")
            return withUnsafeBytes(of: storage) { bytes in
                Move(raw: bytes.load(fromByteOffset: index &* 4, as: UInt32.self))
            }
        }
        @inline(__always) set {
            assert(index >= 0 && index < count, "MoveList index out of range")
            withUnsafeMutableBytes(of: &storage) { bytes in
                bytes.storeBytes(of: newValue.raw, toByteOffset: index &* 4, as: UInt32.self)
            }
        }
    }
}

extension MoveList: RandomAccessCollection, MutableCollection {
    public typealias Index = Int
    public typealias Element = Move

    @inline(__always) public var startIndex: Int { 0 }
    @inline(__always) public var endIndex: Int { count }
}
