// Ported 1:1 from src/engine/pgn.ts.

/// TS `PgnHeaders` (`{ [key: string]: string }`). Keeps JS object semantics: insertion order is
/// preserved, assigning an existing key keeps its position, and (as `Object.entries` does)
/// array-index-like keys such as "1" enumerate first in ascending numeric order.
public struct PGNHeaders: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public private(set) var pairs: [(key: String, value: String)] = []

    public init() {}

    public init(dictionaryLiteral elements: (String, String)...) {
        for (k, v) in elements { self[k] = v }
    }

    public subscript(key: String) -> String? {
        get { pairs.first { $0.key == key }?.value }
        set {
            if let i = pairs.firstIndex(where: { $0.key == key }) {
                if let v = newValue { pairs[i].value = v } else { pairs.remove(at: i) }
            } else if let v = newValue {
                pairs.append((key, v))
            }
        }
    }

    public var isEmpty: Bool { pairs.isEmpty }
    public var count: Int { pairs.count }

    /// Entries in JS `Object.entries` order.
    public var entries: [(key: String, value: String)] {
        let indexLike = pairs.filter { isArrayIndexKey($0.key) }
            .sorted { UInt32($0.key)! < UInt32($1.key)! }
        return indexLike + pairs.filter { !isArrayIndexKey($0.key) }
    }

    public static func == (lhs: PGNHeaders, rhs: PGNHeaders) -> Bool {
        lhs.pairs.count == rhs.pairs.count
            && zip(lhs.pairs, rhs.pairs).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public func hash(into hasher: inout Hasher) {
        for (k, v) in pairs { hasher.combine(k); hasher.combine(v) }
    }
}

/// A canonical array index: decimal digits without leading zeros, below 2^32 - 1.
private func isArrayIndexKey(_ key: String) -> Bool {
    guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return false }
    if key.count > 1 && key.first == "0" { return false }
    guard let n = UInt32(key) else { return false }
    return n != UInt32.max
}

public enum PGNError: Error, Equatable, Sendable, CustomStringConvertible {
    /// TS `throw new Error('Illegal or unparseable PGN move: ' + tok)`.
    case illegalMove(String)

    public var description: String {
        switch self {
        case .illegalMove(let token): return "Illegal or unparseable PGN move: \(token)"
        }
    }
}

/// Export a game as PGN with standard seven-tag-roster-ish headers.
public func toPGN(_ game: Game, headers: PGNHeaders = [:]) -> String {
    var h: PGNHeaders = [
        "Event": "Adaptive Chess",
        "Site": "Local",
        "Date": headers["Date"] ?? "????.??.??",
        "Round": "-",
        "White": "White",
        "Black": "Black",
        "Result": game.result?.score ?? "*",
    ]
    for (k, v) in headers.pairs { h[k] = v } // `...headers`
    if game.startFEN != Position.startFEN {
        h["SetUp"] = "1"
        h["FEN"] = game.startFEN
    }
    var out = ""
    for (k, v) in h.entries { out += "[\(k) \"\(v)\"]\n" }
    out += "\n"
    let sans = game.sanLine()
    var tokens: [String] = []
    // A game starting from a FEN with Black to move numbers as "N... move".
    let startPos = game.positionAt(0)
    var moveNo = startPos.fullmove
    var whiteToMove = startPos.turn == .white
    for i in 0..<sans.count {
        if whiteToMove { tokens.append("\(moveNo)."); tokens.append(sans[i]) }
        else {
            if i == 0 { tokens.append("\(moveNo)..."); tokens.append(sans[i]) }
            else { tokens.append(sans[i]) }
            moveNo += 1
        }
        whiteToMove.toggle()
    }
    tokens.append(game.result?.score ?? "*")
    // Wrap at ~80 chars (JS string lengths are UTF-16 code units).
    var line = "", body = ""
    for t in tokens {
        if line.utf16.count + t.utf16.count + 1 > 80 { body += line + "\n"; line = t }
        else { line = line.isEmpty ? t : line + " " + t }
    }
    body += line + "\n"
    return out + body
}

/// Parse a single-game PGN. Returns the reconstructed Game and its headers.
/// Throws `PGNError.illegalMove` for a bad move token and `FENError` for a bad FEN header.
public func fromPGN(_ pgn: String) throws -> (game: Game, headers: PGNHeaders) {
    // TS: /^\s*\[(\w+)\s+"([^"]*)"\]\s*$/gm
    let headerRe = /^\s*\[([A-Za-z0-9_]+)\s+"([^"]*)"\]\s*$/.anchorsMatchLineEndings()
    var headers = PGNHeaders()
    for m in pgn.matches(of: headerRe) { headers[String(m.output.1)] = String(m.output.2) }

    var body = pgn.replacing(headerRe, with: " ")
    body = body
        .replacing(/\{[^}]*\}/, with: " ")   // comments
        .replacing(/;[^\n]*/, with: " ")     // rest-of-line comments
        .replacing(/\$[0-9]+/, with: " ")    // NAGs
    // Strip nested variations
    var prev = ""
    while prev != body { prev = body; body = body.replacing(/\([^()]*\)/, with: " ") }

    var game = try Game(fen: headers["FEN"] ?? Position.startFEN)
    let tokens = body.split(whereSeparator: isJavaScriptWhitespace).filter { !$0.isEmpty }
    for tok in tokens {
        if tok == "1-0" || tok == "0-1" || tok == "1/2-1/2" || tok == "*" { break }
        if isMoveNumberToken(tok) { continue }
        let cleaned = strippingMoveNumberPrefix(tok) // "1.e4" style
        if cleaned.isEmpty { continue }
        if game.playSAN(String(cleaned)) == nil { throw PGNError.illegalMove(String(tok)) }
    }
    return (game, headers)
}

/// TS `/^\d+\.+$/`.
private func isMoveNumberToken(_ tok: Substring) -> Bool {
    let digits = tok.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return false }
    let rest = tok.dropFirst(digits.count)
    return !rest.isEmpty && rest.allSatisfy { $0 == "." }
}

/// TS `tok.replace(/^\d+\.+/, '')`.
private func strippingMoveNumberPrefix(_ tok: Substring) -> Substring {
    let digits = tok.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return tok }
    let afterDigits = tok.dropFirst(digits.count)
    let dots = afterDigits.prefix { $0 == "." }
    guard !dots.isEmpty else { return tok }
    return afterDigits.dropFirst(dots.count)
}
