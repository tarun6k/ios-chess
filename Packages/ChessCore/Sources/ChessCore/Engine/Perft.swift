// Ported from src/engine/perft.ts.

extension Position {
    /// Perft node count with legality via make/unmake. The position is restored before returning.
    public mutating func perft(depth: Int) -> Int {
        if depth == 0 { return 1 }
        var moves = MoveList()
        generatePseudoLegalMoves(into: &moves)
        let us = turn
        let them = us.opponent
        var nodes = 0
        for i in 0..<moves.count {
            makeMove(moves[i])
            if !isAttacked(kingSquare(us), by: them) {
                nodes += depth == 1 ? 1 : perft(depth: depth - 1)
            }
            unmakeMove()
        }
        return nodes
    }
}
