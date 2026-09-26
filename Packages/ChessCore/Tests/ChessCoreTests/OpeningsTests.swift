import Testing
@testable import ChessCore

@Suite("openings")
struct OpeningsTests {
    let fx = AIFixtures.shared

    @Test("the book has the TS lines, names and tags, in order")
    func bookMatches() {
        #expect(openingBook == fx.book)
        #expect(openingBook.count == 22)
        #expect(Set(openingBook.map(\.name)).count == openingBook.count)
    }

    @Test("every book line is legal SAN from the start position")
    func linesAreLegal() {
        for line in openingBook {
            var game = Game()
            game.playLine(line.san)
            #expect(game.sanLine() == line.san, "\(line.name)")
        }
    }

    @Test("identifyOpening returns the longest match with at least two plies")
    func identify() {
        for c in fx.identify {
            #expect(identifyOpening(c.sans) == c.result, "\(c.sans)")
        }
        #expect(fx.identify.count >= 10)
        #expect(identifyOpening(["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"]) == OpeningMatch(name: "Ruy Lopez", plies: 6))
        // Ties keep the first line in the book.
        #expect(identifyOpening(["e4", "e5", "Nf3", "Nc6"])?.name == "Italian Game")
        #expect(identifyOpening(["d4"]) == nil)
    }

    @Test("bookContinuations returns next moves, preferring tagged lines when any match")
    func continuations() {
        for c in fx.continuations {
            #expect(bookContinuations(c.sans, preferTags: c.preferTags) == c.result, "\(c.sans) \(c.preferTags ?? [])")
        }
        #expect(fx.continuations.count >= 10)
        #expect(bookContinuations(["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6", "d3"]).isEmpty)
        #expect(bookContinuations(["e4", "c5"], preferTags: [.space]) == ["Nf3", "Nc3"]) // no space line: exact list
        #expect(bookContinuations(["e4", "c5"], preferTags: [.closed]) == ["Nc3"])
    }
}
