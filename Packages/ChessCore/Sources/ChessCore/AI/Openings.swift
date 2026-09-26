// Ported 1:1 from src/ai/openings.ts.
//
// TypeScript name → Swift name
//   OpeningLine.tags union            → OpeningTag (raw values are the TS strings)
//   BOOK                              → openingBook
//   identifyOpening(sans)             → identifyOpening(_:) returning OpeningMatch?
//   bookContinuations(sans, tags?)    → bookContinuations(_:preferTags:)

// Compact opening book: named SAN lines. Used for
//  - recognizing/naming what the player opens with,
//  - AI book moves in the first plies,
//  - anti-style preparation (see adaptation.ts).

/// character of a line, used by adaptation
public enum OpeningTag: String, Hashable, Sendable, Codable, CaseIterable {
    case open, closed, sharp, solid, space
}

public struct OpeningLine: Hashable, Sendable, Codable {
    public var name: String
    public var san: [String]
    public var tags: [OpeningTag]

    public init(name: String, san: [String], tags: [OpeningTag]) {
        self.name = name
        self.san = san
        self.tags = tags
    }
}

/// TS `BOOK`.
public let openingBook: [OpeningLine] = [
    OpeningLine(name: "Italian Game", san: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6", "d3"], tags: [.open, .solid]),
    OpeningLine(name: "Ruy Lopez", san: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O"], tags: [.open, .solid]),
    OpeningLine(name: "Scotch Game", san: ["e4", "e5", "Nf3", "Nc6", "d4", "exd4", "Nxd4"], tags: [.open, .sharp]),
    OpeningLine(name: "King's Gambit", san: ["e4", "e5", "f4", "exf4", "Nf3"], tags: [.open, .sharp]),
    OpeningLine(name: "Sicilian Defence", san: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3"], tags: [.open, .sharp]),
    OpeningLine(name: "Sicilian, Closed", san: ["e4", "c5", "Nc3", "Nc6", "g3", "g6", "Bg2", "Bg7", "d3"], tags: [.closed, .solid]),
    OpeningLine(name: "French Defence", san: ["e4", "e6", "d4", "d5", "e5", "c5", "c3", "Nc6", "Nf3"], tags: [.closed, .solid]),
    OpeningLine(name: "Caro-Kann Defence", san: ["e4", "c6", "d4", "d5", "Nc3", "dxe4", "Nxe4", "Bf5"], tags: [.closed, .solid]),
    OpeningLine(name: "Scandinavian Defence", san: ["e4", "d5", "exd5", "Qxd5", "Nc3", "Qa5", "d4"], tags: [.open, .solid]),
    OpeningLine(name: "Pirc Defence", san: ["e4", "d6", "d4", "Nf6", "Nc3", "g6", "Nf3", "Bg7"], tags: [.closed, .solid]),
    OpeningLine(name: "Queen's Gambit Declined", san: ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "Bg5", "Be7", "e3"], tags: [.closed, .solid]),
    OpeningLine(name: "Queen's Gambit Accepted", san: ["d4", "d5", "c4", "dxc4", "Nf3", "Nf6", "e3", "e6", "Bxc4"], tags: [.open, .solid]),
    OpeningLine(name: "Slav Defence", san: ["d4", "d5", "c4", "c6", "Nf3", "Nf6", "Nc3", "dxc4", "a4"], tags: [.closed, .solid]),
    OpeningLine(name: "King's Indian Defence", san: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7", "e4", "d6", "Nf3", "O-O"], tags: [.closed, .sharp, .space]),
    OpeningLine(name: "Nimzo-Indian Defence", san: ["d4", "Nf6", "c4", "e6", "Nc3", "Bb4", "e3", "O-O"], tags: [.closed, .solid]),
    OpeningLine(name: "Grünfeld Defence", san: ["d4", "Nf6", "c4", "g6", "Nc3", "d5", "cxd5", "Nxd5", "e4"], tags: [.open, .sharp]),
    OpeningLine(name: "London System", san: ["d4", "d5", "Nf3", "Nf6", "Bf4", "e6", "e3", "Bd6", "Bg3"], tags: [.closed, .solid]),
    OpeningLine(name: "English Opening", san: ["c4", "e5", "Nc3", "Nf6", "g3", "d5", "cxd5", "Nxd5", "Bg2"], tags: [.closed, .space]),
    OpeningLine(name: "Réti Opening", san: ["Nf3", "d5", "c4", "e6", "g3", "Nf6", "Bg2"], tags: [.closed, .solid]),
    OpeningLine(name: "Vienna Game", san: ["e4", "e5", "Nc3", "Nf6", "f4", "d5", "fxe5", "Nxe4"], tags: [.open, .sharp]),
    OpeningLine(name: "Four Knights Game", san: ["e4", "e5", "Nf3", "Nc6", "Nc3", "Nf6", "Bb5", "Bb4"], tags: [.open, .solid]),
    OpeningLine(name: "Queen's Pawn Game", san: ["d4", "d5", "Nf3", "Nf6", "e3", "e6", "Bd3"], tags: [.closed, .solid]),
]

/// TS `{ name: string; plies: number }` returned by `identifyOpening`.
public struct OpeningMatch: Hashable, Sendable, Codable {
    public var name: String
    public var plies: Int

    public init(name: String, plies: Int) {
        self.name = name
        self.plies = plies
    }
}

/// Longest named line matching the game's SAN prefix.
public func identifyOpening(_ sans: [String]) -> OpeningMatch? {
    var best: OpeningMatch? = nil
    for line in openingBook {
        var n = 0
        while n < line.san.count && n < sans.count && line.san[n] == sans[n] { n += 1 }
        if n >= 2 && (best == nil || n > best!.plies) { best = OpeningMatch(name: line.name, plies: n) }
    }
    return best
}

/// Book continuations for the current SAN prefix, optionally filtered by tags.
/// Returns candidate next SAN moves.
public func bookContinuations(_ sans: [String], preferTags: [OpeningTag]? = nil) -> [String] {
    var exact: [String] = []
    var preferred: [String] = []
    for line in openingBook {
        if line.san.count <= sans.count { continue }
        var match = true
        for i in 0..<sans.count {
            if line.san[i] != sans[i] { match = false; break }
        }
        if !match { continue }
        let next = line.san[sans.count]
        exact.append(next)
        if let preferTags, preferTags.contains(where: { line.tags.contains($0) }) { preferred.append(next) }
    }
    return preferred.isEmpty ? exact : preferred
}
