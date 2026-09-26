// Ported 1:1 from src/engine/san.ts. The three functions keep their TS names.

private let fileLetters: [Character] = ["a", "b", "c", "d", "e", "f", "g", "h"]

/// Standard algebraic notation for a legal move in `pos` (side to move).
/// Appends '+' / '#' by making the move and testing the reply position.
public func toSAN(_ pos: Position, _ move: Move, legalMoves: [Move]? = nil) -> String {
    let from = move.from, to = move.to, flags = move.flags, promo = move.promotion
    let piece = pos.board[from]
    let type = piece.type
    var san: String

    if flags.contains(.castleKingside) { san = "O-O" }
    else if flags.contains(.castleQueenside) { san = "O-O-O" }
    else {
        let isCapture = !pos.board[to].isEmpty || flags.contains(.enPassant)
        if type == .pawn {
            san = (isCapture ? String(fileLetters[fileOf(from)]) + "x" : "") + squareName(to)
            if promo != .empty { san += "=" + String(promo.symbol) }
        } else {
            // Disambiguation among same-type pieces that can also reach `to`.
            let legals = legalMoves ?? pos.generateLegalMoves()
            var sameFile = false, sameRank = false, others = false
            for m in legals {
                if m == move { continue }
                let f = m.from
                if m.to != to || f == from { continue }
                if pos.board[f].type != type { continue }
                others = true
                if fileOf(f) == fileOf(from) { sameFile = true }
                if rankOf(f) == rankOf(from) { sameRank = true }
            }
            var dis = ""
            if others {
                if !sameFile { dis = String(fileLetters[fileOf(from)]) }
                else if !sameRank { dis = String(rankOf(from) + 1) }
                else { dis = squareName(from) }
            }
            san = String(type.symbol) + dis + (isCapture ? "x" : "") + squareName(to)
        }
    }

    var after = pos.clone()
    after.makeMove(move)
    if after.isInCheck() { san += after.hasLegalMoves ? "+" : "#" }
    return san
}

/// Strip decorations that do not affect move identity.
/// TS: `san.replace(/[+#!?]+$/g, '').replace(/^([RNBQK])([a-h1-8]?)x/, '$1$2x').trim()`
/// (the second replace rewrites the match to itself and is therefore a no-op).
public func normalizeSAN(_ san: String) -> String {
    var s = Substring(san)
    while let last = s.last, last == "+" || last == "#" || last == "!" || last == "?" {
        s.removeLast()
    }
    return String(trimmingJavaScriptWhitespace(s))
}

/// Parse a SAN token against the legal moves of `pos`. Returns the move or nil.
public func fromSAN(_ pos: Position, _ san: String) -> Move? {
    let target = normalizeSAN(san).replacing("0", with: "O") // tolerate 0-0
    let legals = pos.generateLegalMoves()
    for m in legals {
        if normalizeSAN(toSAN(pos, m, legalMoves: legals)) == target { return m }
    }
    // Tolerate long algebraic (e2e4, e7e8q) as a fallback.
    if let lam = parseLongAlgebraic(target) {
        for m in legals {
            if squareName(m.from) == lam.from && squareName(m.to) == lam.to {
                let promo = m.promotion
                let want: PieceType
                if let letter = lam.promotion {
                    want = PieceType(symbol: Character(letter.uppercased())) ?? .empty
                } else {
                    want = promo != .empty ? .queen : .empty
                }
                if promo == want { return m }
            }
        }
    }
    return nil
}

/// TS regex `/^([a-h][1-8])[-x]?([a-h][1-8])(?:=?([QRBNqrbn]))?$/`.
private func parseLongAlgebraic(_ s: String) -> (from: String, to: String, promotion: Character?)? {
    let chars = Array(s)
    var i = 0
    func square() -> String? {
        guard i + 1 < chars.count else { return nil }
        let f = chars[i], r = chars[i + 1]
        guard ("a"..."h").contains(f), ("1"..."8").contains(r) else { return nil }
        i += 2
        return String(f) + String(r)
    }
    guard let from = square() else { return nil }
    if i < chars.count, chars[i] == "-" || chars[i] == "x" { i += 1 }
    guard let to = square() else { return nil }
    var promotion: Character? = nil
    if i < chars.count {
        if chars[i] == "=" { i += 1 }
        guard i < chars.count, "QRBNqrbn".contains(chars[i]) else { return nil }
        promotion = chars[i]
        i += 1
    }
    guard i == chars.count else { return nil }
    return (from, to, promotion)
}

/// JS `String.prototype.trim`: strips Unicode white space and line terminators at both ends.
func trimmingJavaScriptWhitespace(_ s: Substring) -> Substring {
    var out = s
    while let first = out.first, isJavaScriptWhitespace(first) { out.removeFirst() }
    while let last = out.last, isJavaScriptWhitespace(last) { out.removeLast() }
    return out
}

/// JS `\s`: WhiteSpace (Zs + TAB, VT, FF, NBSP, BOM) and LineTerminator (LF, CR, LS, PS).
@inline(__always) func isJavaScriptWhitespace(_ c: Character) -> Bool {
    switch c {
    case "\t", "\n", "\u{0B}", "\u{0C}", "\r", " ", "\u{A0}", "\u{1680}", "\u{2028}", "\u{2029}",
         "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}":
        return true
    default:
        return ("\u{2000}"..."\u{200A}").contains(c)
    }
}
