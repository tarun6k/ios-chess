// Ported 1:1 from src/ai/search.ts.
//
// TypeScript name → Swift name
//   MATE                                → mateScore
//   SearchOptions / RootMove /
//   SearchResult                        → same names (`best: Move | 0` → `Move?`, `moveTimeMs` is a Double
//                                          because controller.ts passes fractional budgets such as remaining/40)
//   class Search { clear, search }      → struct Search { clear(), search(_:options:) } — a struct so the
//                                          recursive hot path mutates `self` without dynamic exclusivity checks
//   class TimeUp                        → TimeUp (thrown by the node-count/deadline check, caught in `search`)
//   pathKeys: Map<string, number>       → historyCounts: [UInt64: Int] + path: [UInt64] — keyed by the 64-bit
//                                          Zobrist hash instead of its base-36 `hashKey` string (a bijection)
//
// Cooperative cancellation: `SearchOptions.isCancelled` is polled at the same point as the TS deadline
// (every 2048 nodes). A cancelled search behaves exactly like a time-out: the result of the last
// completed depth is returned. `SearchCancellation` is a ready-made thread-safe flag for it.
//
// The TS works on the caller's Position and restores it in `finally` blocks; here `search` works on
// a copy, so nothing needs restoring when a `TimeUp` unwinds the recursion.

import os

/// TS `MATE`: the score of a checkmate delivered at ply 0; mate-in-n scores are `mateScore - plies`.
public let mateScore = 100_000
let mateThreshold = mateScore - 1000

// Transposition table: index by hashLo & mask, verify the full key.
private let ttSize = 1 << 18
private let ttMask = UInt32(ttSize - 1)
private let ttExact: UInt8 = 0, ttLower: UInt8 = 1, ttUpper: UInt8 = 2
/// Stands in for the TS `undefined` slot; the real flags are 0, 1 and 2.
private let ttEmpty: UInt8 = 0xFF
/// Stands in for the TS `±Infinity` window bounds; far beyond any real score.
private let infinity = 1 << 30
private let noMove = Move(raw: 0)

/// TS `interface TTEntry { hi, lo, depth, score, flag, move }`.
private struct TTEntry {
    var key: UInt64 = 0
    var move = noMove
    var score: Int32 = 0
    var depth: Int16 = 0
    var flag = ttEmpty
}

private struct TimeUp: Error {}

public struct SearchOptions: Sendable {
    public var maxDepth: Int
    /// soft time cap in ms — search finishes the current depth then stops
    public var moveTimeMs: Double
    public var params: EvalParams
    /// repetition keys of the game so far (for draw detection at the root path), `Position.hashKey` strings
    public var historyKeys: [String]
    /// Polled every 2048 nodes like the deadline; `true` stops the search after the current node.
    public var isCancelled: (@Sendable () -> Bool)?

    public init(maxDepth: Int, moveTimeMs: Double, params: EvalParams = .neutral, historyKeys: [String] = [],
                isCancelled: (@Sendable () -> Bool)? = nil) {
        self.maxDepth = maxDepth
        self.moveTimeMs = moveTimeMs
        self.params = params
        self.historyKeys = historyKeys
        self.isCancelled = isCancelled
    }
}

public struct RootMove: Hashable, Sendable {
    public var move: Move
    public var score: Int

    public init(move: Move, score: Int) {
        self.move = move
        self.score = score
    }
}

public struct SearchResult: Hashable, Sendable {
    /// nil when the side to move has no legal move (TS `best: 0`).
    public var best: Move?
    /// cp from the searched side's POV
    public var score: Int
    /// depth actually completed
    public var depth: Int
    public var nodes: Int
    /// root moves with exact-ish scores, best first (for persona/blunder selection)
    public var rootMoves: [RootMove]
    public var pv: [Move]

    public init(best: Move?, score: Int, depth: Int, nodes: Int, rootMoves: [RootMove], pv: [Move]) {
        self.best = best
        self.score = score
        self.depth = depth
        self.nodes = nodes
        self.rootMoves = rootMoves
        self.pv = pv
    }
}

/// A thread-safe flag for `SearchOptions.isCancelled`: `cancel()` from any thread, poll from the search.
public final class SearchCancellation: Sendable {
    private let flag = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public func cancel() { flag.withLock { $0 = true } }

    public var isCancelled: Bool { flag.withLock { $0 } }
}

public struct Search {
    private var tt = [TTEntry](repeating: TTEntry(), count: ttSize)
    private var killers: [(Move, Move)] = []
    private var history = [Int32](repeating: 0, count: 2 * 64 * 64)
    private var nodes = 0
    private var deadline = ContinuousClock.now
    private var params = EvalParams.neutral
    /// Occurrences of each key in the game so far (TS seeds `pathKeys` with `historyKeys`).
    private var historyCounts: [UInt64: Int] = [:]
    /// Keys of the positions on the current search path, root child first.
    private var path: [UInt64] = []
    private var isCancelled: (@Sendable () -> Bool)?

    public init() {}

    /// TS `clear()`: forget the transposition table, history heuristic and killers.
    public mutating func clear() {
        tt = [TTEntry](repeating: TTEntry(), count: ttSize)
        for i in history.indices { history[i] = 0 }
        killers = []
    }

    /// Iterative-deepening search. Never throws; always returns the best completed result.
    public mutating func search(_ position: Position, options opts: SearchOptions) -> SearchResult {
        var pos = position
        params = opts.params
        nodes = 0
        killers = [(Move, Move)](repeating: (noMove, noMove), count: 64)
        let clock = ContinuousClock()
        deadline = clock.now + .milliseconds(max(50, opts.moveTimeMs))
        isCancelled = opts.isCancelled
        historyCounts = [:]
        path = []
        for key in opts.historyKeys {
            // A key that is not a `hashKey` can never match a position, exactly like an unmatched TS string.
            if let hash = Zobrist.hash(fromKey: key) { historyCounts[hash, default: 0] += 1 }
        }

        let legal = pos.generateLegalMoves()
        if legal.isEmpty {
            return SearchResult(best: nil, score: pos.isInCheck() ? -mateScore : 0, depth: 0, nodes: 0, rootMoves: [], pv: [])
        }

        var result = SearchResult(
            best: legal[0], score: 0, depth: 0, nodes: 0,
            rootMoves: legal.map { RootMove(move: $0, score: 0) }, pv: [legal[0]]
        )

        let softStop = clock.now + .milliseconds(opts.moveTimeMs * 0.6)
        var depth = 1
        while depth <= opts.maxDepth {
            do {
                let rootMoves = try searchRoot(&pos, depth: depth, prevOrder: result.rootMoves)
                result = SearchResult(
                    best: rootMoves[0].move,
                    score: rootMoves[0].score,
                    depth: depth,
                    nodes: nodes,
                    rootMoves: rootMoves,
                    pv: extractPV(&pos, maxLen: depth)
                )
            } catch {
                break // TimeUp
            }
            if clock.now > softStop { break }
            if result.score > mateThreshold { break } // found a forced mate — play it
            depth += 1
        }
        return result
    }

    /// Root search: every move gets a score. Moves within 250cp of the best get
    /// exact scores (searched with a widened window) so the persona layer can
    /// choose among realistic candidates.
    private mutating func searchRoot(_ pos: inout Position, depth: Int, prevOrder: [RootMove]) throws -> [RootMove] {
        let margin = 250
        var alpha = -infinity
        var scored: [RootMove] = []
        let moves = prevOrder.isEmpty ? pos.generateLegalMoves() : prevOrder.map(\.move)
        scored.reserveCapacity(moves.count)
        for m in moves {
            pos.makeMove(m)
            path.append(pos.hash)
            let child = try alphaBeta(&pos, depth: depth - 1, alpha: -infinity, beta: -(alpha - margin), ply: 1)
            path.removeLast()
            pos.unmakeMove()
            let score = -child
            scored.append(RootMove(move: m, score: score))
            if score > alpha { alpha = score }
        }
        // JS `scored.sort((a, b) => b.score - a.score)` is stable: insertion sort, best first.
        for i in 1..<max(1, scored.count) {
            let item = scored[i]
            var j = i - 1
            while j >= 0 && scored[j].score < item.score {
                scored[j + 1] = scored[j]
                j -= 1
            }
            scored[j + 1] = item
        }
        return scored
    }

    /// TS `isRepetitionDraw`: the position is on the path / in the game twice already, or the 50-move rule.
    @inline(__always) private func isRepetitionDraw(_ pos: Position) -> Bool {
        let key = pos.hash
        var count = historyCounts.isEmpty ? 0 : (historyCounts[key] ?? 0)
        for k in path where k == key { count += 1 }
        return count >= 2 || pos.halfmove >= 100
    }

    /// TS `(this.nodes++ & 2047) === 0 && Date.now() > this.deadline` → `throw new TimeUp()`.
    @inline(__always) private mutating func countNodeAndCheckDeadline() throws {
        let n = nodes
        nodes += 1
        if n & 2047 == 0 {
            if let cancelled = isCancelled, cancelled() { throw TimeUp() }
            if ContinuousClock.now > deadline { throw TimeUp() }
        }
    }

    private mutating func alphaBeta(_ pos: inout Position, depth: Int, alpha: Int, beta: Int, ply: Int) throws -> Int {
        try countNodeAndCheckDeadline()

        if isRepetitionDraw(pos) || pos.isInsufficientMaterial { return 0 }

        let inCheck = pos.isInCheck()
        var depth = depth
        if inCheck { depth += 1 } // check extension

        if depth <= 0 { return try quiescence(&pos, alpha: alpha, beta: beta, ply: ply) }

        // TT probe
        let idx = Int(pos.hashLo & ttMask)
        let entry = tt[idx]
        var ttMove = noMove
        if entry.flag != ttEmpty && entry.key == pos.hash {
            ttMove = entry.move
            if Int(entry.depth) >= depth {
                let s = Int(entry.score)
                if entry.flag == ttExact { return s }
                if entry.flag == ttLower && s >= beta { return s }
                if entry.flag == ttUpper && s <= alpha { return s }
            }
        }

        var moves = MoveList()
        pos.generatePseudoLegalMoves(into: &moves)
        orderMoves(pos, &moves, ttMove: ttMove, ply: ply)

        var alpha = alpha
        var bestScore = -infinity
        var bestMove = noMove
        var legalCount = 0
        let alphaOrig = alpha
        let us = pos.turn
        let them = us.opponent

        for i in 0..<moves.count {
            let m = moves[i]
            pos.makeMove(m)
            if pos.isAttacked(pos.kingSquare(us), by: them) { pos.unmakeMove(); continue }
            legalCount += 1
            path.append(pos.hash)
            let child = try alphaBeta(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            path.removeLast()
            pos.unmakeMove()
            let score = -child
            if score > bestScore {
                bestScore = score
                bestMove = m
                if score > alpha {
                    alpha = score
                    if alpha >= beta {
                        // killer/history for quiet moves
                        if pos.board[m.to].isEmpty && !m.flags.contains(.enPassant) {
                            storeKiller(m, ply: ply)
                            history[(pos.turn.rawValue * 64 + m.from) * 64 + m.to] &+= Int32(truncatingIfNeeded: depth * depth)
                        }
                        break
                    }
                }
            }
        }

        if legalCount == 0 { return inCheck ? -mateScore + ply : 0 }

        let flag = bestScore <= alphaOrig ? ttUpper : bestScore >= beta ? ttLower : ttExact
        tt[idx] = TTEntry(key: pos.hash, move: bestMove, score: Int32(bestScore), depth: Int16(depth), flag: flag)
        return bestScore
    }

    /// TS `const k = this.killers[ply] ?? (this.killers[ply] = [0, 0]); if (k[0] !== m) { k[1] = k[0]; k[0] = m; }`
    @inline(__always) private mutating func storeKiller(_ m: Move, ply: Int) {
        if ply >= killers.count {
            killers.append(contentsOf: repeatElement((noMove, noMove), count: ply + 1 - killers.count))
        }
        if killers[ply].0 != m {
            killers[ply].1 = killers[ply].0
            killers[ply].0 = m
        }
    }

    private mutating func quiescence(_ pos: inout Position, alpha: Int, beta: Int, ply: Int) throws -> Int {
        try countNodeAndCheckDeadline()

        let side = pos.turn == .white ? 1 : -1
        let stand = side * evaluate(pos, params: params)
        if stand >= beta { return stand }
        var alpha = alpha
        if stand > alpha { alpha = stand }
        if ply > 40 { return stand }

        var moves = MoveList()
        pos.generatePseudoLegalMoves(into: &moves)
        // captures and promotions only (TS `movePromo(m) >= 5`: queen promotions)
        var tactical = MoveList()
        for i in 0..<moves.count {
            let m = moves[i]
            if !pos.board[m.to].isEmpty || m.flags.contains(.enPassant) || m.promotion.rawValue >= 5 { tactical.append(m) }
        }
        sortByMvvLva(pos, &tactical)

        let us = pos.turn
        let them = us.opponent
        var best = stand
        for i in 0..<tactical.count {
            let m = tactical[i]
            // Delta pruning: skip hopeless captures
            let victim = pos.board[m.to]
            if !victim.isEmpty && stand + pieceValues[victim.type.rawValue] + 200 < alpha { continue }
            pos.makeMove(m)
            if pos.isAttacked(pos.kingSquare(us), by: them) { pos.unmakeMove(); continue }
            let child = try quiescence(&pos, alpha: -beta, beta: -alpha, ply: ply + 1)
            pos.unmakeMove()
            let score = -child
            if score > best {
                best = score
                if score > alpha {
                    alpha = score
                    if alpha >= beta { break }
                }
            }
        }
        return best
    }

    /// TS `mvvLva`: `v * 10 - PIECE_VALUE[attacker] / 10 + promo * 50` (every piece value is a multiple of 10).
    @inline(__always) private func mvvLva(_ pos: Position, _ m: Move) -> Int {
        let victim = pos.board[m.to]
        let attacker = pos.board[m.from]
        let v = victim.isEmpty ? (m.flags.contains(.enPassant) ? 100 : 0) : pieceValues[victim.type.rawValue]
        return v * 10 - pieceValues[attacker.type.rawValue] / 10 + m.promotion.rawValue * 50
    }

    /// JS `tactical.sort((a, b) => mvvLva(b) - mvvLva(a))` — stable, descending.
    private func sortByMvvLva(_ pos: Position, _ moves: inout MoveList) {
        let n = moves.count
        if n < 2 { return }
        withUnsafeTemporaryAllocation(of: Int.self, capacity: n) { scores in
            for i in 0..<n { scores[i] = mvvLva(pos, moves[i]) }
            insertionSortDescending(&moves, scores, count: n)
        }
    }

    private func orderMoves(_ pos: Position, _ moves: inout MoveList, ttMove: Move, ply: Int) {
        let killer = ply < killers.count ? killers[ply] : (noMove, noMove)
        let n = moves.count
        if n < 2 { return }
        withUnsafeTemporaryAllocation(of: Int.self, capacity: n) { scores in
            for i in 0..<n {
                let m = moves[i]
                if m == ttMove { scores[i] = 1_000_000_000; continue }
                let victim = pos.board[m.to]
                if !victim.isEmpty || m.flags.contains(.enPassant) { scores[i] = 1_000_000 + mvvLva(pos, m); continue }
                if m == killer.0 { scores[i] = 900_000; continue }
                if m == killer.1 { scores[i] = 800_000; continue }
                scores[i] = Int(history[(pos.turn.rawValue * 64 + m.from) * 64 + m.to])
            }
            // simple insertion sort by paired score (moves lists are short)
            insertionSortDescending(&moves, scores, count: n)
        }
    }

    /// The TS insertion sort: shifts only while `scores[j] < s`, so equal scores keep their order.
    @inline(__always) private func insertionSortDescending(_ moves: inout MoveList, _ scores: UnsafeMutableBufferPointer<Int>, count n: Int) {
        for i in 1..<n {
            let m = moves[i], s = scores[i]
            var j = i - 1
            while j >= 0 && scores[j] < s {
                moves[j + 1] = moves[j]
                scores[j + 1] = scores[j]
                j -= 1
            }
            moves[j + 1] = m
            scores[j + 1] = s
        }
    }

    private func extractPV(_ pos: inout Position, maxLen: Int) -> [Move] {
        var pv: [Move] = []
        var count = 0
        var seen = Set<UInt64>()
        while count < maxLen {
            let entry = tt[Int(pos.hashLo & ttMask)]
            if entry.flag == ttEmpty || entry.key != pos.hash || entry.move == noMove { break }
            let legal = pos.generateLegalMoves()
            if !legal.contains(entry.move) { break }
            if seen.contains(pos.hash) { break }
            seen.insert(pos.hash)
            pv.append(entry.move)
            pos.makeMove(entry.move)
            count += 1
        }
        for _ in 0..<count { pos.unmakeMove() }
        return pv
    }
}
