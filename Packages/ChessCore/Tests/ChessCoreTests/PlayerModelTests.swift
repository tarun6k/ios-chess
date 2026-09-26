import Foundation
import Testing
@testable import ChessCore

// playerModel.ts against values the TS produced (adaptation-fixtures.json).

@Suite("Player model")
struct PlayerModelTests {
    let fx = AdaptationFixtures.shared
    static let colors: [PieceColor] = [.white, .black]

    @Test("newPlayerModel defaults and JSON shape")
    func fresh() throws {
        let model = PlayerModel()
        #expect(model.version == 1)
        #expect(model.rating == 800)
        #expect(model.ratingHistory.isEmpty)
        #expect(model.wins == 0 && model.losses == 0 && model.draws == 0 && model.streak == 0)
        #expect(model.features == StyleFeatures(games: 0, avgCaptureRate: 0, avgEarlyQueenPly: 24, avgCastlePly: 30,
                                                avgChecksPerGame: 0, avgPawnStorm: 0, avgTradeRate: 0, avgCpLoss: 0, avgThinkMs: 0))
        #expect(model.weaknesses.entries.allSatisfy { $0.count == 0 })
        #expect(model.weaknesses.entries.map(\.key) == WeaknessKey.allCases)
        #expect(model.openings.isEmpty)
        #expect(model.lastAdaptation == nil)
        let json = try JSONEncoder().encode(model)
        #expect(try canonicalJSON(json) == canonicalJSON(fx.replay.fresh))
        #expect(!String(decoding: json, as: UTF8.self).contains("lastAdaptation"))
        // The fixture keys are the TS keys.
        let keys = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any]).keys.sorted()
        #expect(keys == ["draws", "features", "losses", "openings", "rating", "ratingHistory", "streak", "version", "weaknesses", "wins"])
        let weak = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])["weaknesses"] as? [String: Int]
        #expect(weak?.keys.sorted() == ["back-rank", "endgame", "hanging-pieces", "king-safety", "missed-tactics", "opening"])
    }

    @Test("the fixture games replay to the TS results", arguments: AdaptationFixtures.shared.games)
    func gamesReplay(_ c: AdaptationFixtures.GameCase) throws {
        let game = try fx.build(c)
        #expect(game.history.count == c.sans.count)
        #expect(game.result?.winner == c.result?.winner)
        #expect((game.result == nil) == (c.result == nil))
        #expect(game.history.map(\.thinkMs) == c.thinkMs)
        #expect(game.history.map(\.thinkMs) == c.sans.indices.map(AdaptationFixtures.thinkFor))
    }

    @Test("fact extraction matches the TS for both colours", arguments: AdaptationFixtures.shared.games, colors)
    func facts(_ c: AdaptationFixtures.GameCase, _ color: PieceColor) throws {
        let game = try fx.build(c)
        #expect(AdaptationFixtures.Facts(extractFacts(game, playerColor: color)) == c.facts[color])
    }

    @Test("facts spelled out on Scholar's mate")
    func scholarsFacts() throws {
        let game = try fx.build(try #require(fx.game("scholars")))
        let white = extractFacts(game, playerColor: .white)
        #expect(white.captureRate == 0.25) // Qxf7# out of 4 moves
        #expect(white.earlyQueenPly == 2) // Qh5
        #expect(white.castlePly == 30) // never castled
        #expect(white.checks == 1) // the mate
        #expect(white.pawnStorm == 0)
        #expect(white.tradeRate == 0)
        #expect(white.avgThinkMs == 811) // only ply 3 carried a non-zero thinkMs for White
        #expect(white.openingName == "Italian Game")
        let black = extractFacts(game, playerColor: .black)
        #expect(black.captureRate == 0)
        #expect(black.earlyQueenPly == 24)
        #expect(black.checks == 0)
        #expect(black.avgThinkMs == 811) // (674 + 948) / 2
    }

    @Test("weakness classification from the real analysis", arguments: AdaptationFixtures.shared.games, colors)
    func weaknessesReal(_ c: AdaptationFixtures.GameCase, _ color: PieceColor) throws {
        let game = try fx.build(c)
        let expected = try weaknessMap(c.weaknesses[color])
        #expect(extractWeaknesses(game, playerColor: color, analysis: c.analysis) == expected)
    }

    @Test("weakness classification from the synthetic analysis", arguments: AdaptationFixtures.shared.games, colors)
    func weaknessesSynthetic(_ c: AdaptationFixtures.GameCase, _ color: PieceColor) throws {
        let game = try fx.build(c)
        let expected = try weaknessMap(c.synthetic.weaknesses[color])
        #expect(extractWeaknesses(game, playerColor: color, analysis: c.synthetic.analysis) == expected)
        // Every rule fires somewhere in the synthetic set.
        for m in c.synthetic.analysis {
            #expect(m.judgment == AIEngine.judge(cpLoss: m.cpLoss, isBest: m.bestUci == m.uci))
        }
    }

    @Test("an unfinished game counts as a draw for the record but as not-won for king safety")
    func unfinishedGame() throws {
        let c = try #require(fx.game("kings-gambit-unfinished"))
        let game = try fx.build(c)
        #expect(game.result == nil)
        // White never castled; TS `winner !== null && winner !== playerColor` is true for `undefined`.
        #expect(extractWeaknesses(game, playerColor: .white, analysis: [])[.kingSafety] == 1)
        #expect(extractWeaknesses(game, playerColor: .black, analysis: [])[.kingSafety] == 1)
        var model = PlayerModel()
        updateModelAfterGame(&model, game: game, playerColor: .white, analysis: nil, vsAI: true, aiElo: 1000, now: fx.now)
        #expect(model.draws == 1 && model.wins == 0 && model.losses == 0 && model.streak == 0)
        #expect(model.rating == 812) // scored 0.5 vs 1000 with K = 48
    }

    @Test("a draw and a win do not bump king safety")
    func kingSafetyRule() throws {
        var game = try Game(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        game.playLine(["e4", "e5"])
        game.resign(.black)
        #expect(extractWeaknesses(game, playerColor: .white, analysis: []).isEmpty)
        #expect(extractWeaknesses(game, playerColor: .black, analysis: [])[.kingSafety] == 1)
        var drawn = try Game(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        drawn.playLine(["e4", "e5"])
        drawn.offerDraw(.white)
        let accepted = drawn.acceptDraw()
        #expect(accepted)
        #expect(drawn.result?.winner == nil && drawn.result != nil)
        #expect(extractWeaknesses(drawn, playerColor: .white, analysis: []).isEmpty)
        #expect(extractWeaknesses(drawn, playerColor: .black, analysis: []).isEmpty)
    }

    @Test("style classification", arguments: AdaptationFixtures.shared.classify)
    func classify(_ c: AdaptationFixtures.ClassifyCase) throws {
        let r = classifyStyle(c.features)
        #expect(r.label == c.label)
        var scores: [StyleLabel: Int] = [:]
        for (k, v) in c.scores { scores[try #require(StyleLabel(rawValue: k))] = v }
        #expect(r.scores == scores)
    }

    @Test("Elo update: K = 48 for the first 10 games, then 24; floor 200", arguments: AdaptationFixtures.shared.rating.steps)
    func ratingStep(_ s: AdaptationFixtures.RatingStep) {
        var m = PlayerModel()
        m.rating = s.rating
        m.features.games = s.games
        updateRating(&m, aiElo: s.aiElo, score: s.score, now: fx.now + 1)
        #expect(m.rating == s.result)
        #expect(m.ratingHistory == s.history)
    }

    @Test("K factor switches after the tenth game")
    func kFactor() {
        var early = PlayerModel()
        early.features.games = 9
        updateRating(&early, aiElo: 800, score: 1, now: 0)
        #expect(early.rating == 824) // 800 + 48 * 0.5
        var later = PlayerModel()
        later.features.games = 10
        updateRating(&later, aiElo: 800, score: 1, now: 0)
        #expect(later.rating == 812) // 800 + 24 * 0.5
    }

    @Test("ratingHistory is capped at 200 entries")
    func ratingCap() {
        var m = PlayerModel()
        for i in 0..<fx.rating.cap.calls {
            updateRating(&m, aiElo: 1000, score: i % 3 == 0 ? 1 : i % 3 == 1 ? 0 : 0.5, now: fx.now + i * 1000)
        }
        #expect(fx.rating.cap.calls == 205)
        #expect(m.ratingHistory.count == 200)
        #expect(m.ratingHistory.first?.t == fx.now + 5 * 1000)
        #expect(m == fx.rating.cap.model)
    }

    @Test("topWeaknesses sorts by count, keeps key order on ties and drops zeros", arguments: AdaptationFixtures.shared.topWeaknesses)
    func top(_ c: AdaptationFixtures.TopWeaknessesCase) {
        var model = PlayerModel()
        model.weaknesses = c.weaknesses
        let result = c.n.map { topWeaknesses(model, n: $0) } ?? topWeaknesses(model)
        #expect(result.map(\.key) == c.result.map(\.key))
        #expect(result.map(\.count) == c.result.map(\.count))
    }

    @Test("replaying the TS games reproduces every model snapshot and the stored blob")
    func replay() throws {
        let built = try fx.builtGames()
        var model = PlayerModel()
        for (i, s) in fx.replay.steps.enumerated() {
            let game = try #require(built[s.step.game])
            let analysis: [AnalyzedMove]? = switch s.step.analysis {
            case "real": try #require(fx.game(s.step.game)).analysis
            case "synthetic": try #require(fx.game(s.step.game)).synthetic.analysis
            default: nil
            }
            let facts = updateModelAfterGame(
                &model, game: game, playerColor: s.step.playerColor, analysis: analysis,
                vsAI: s.step.vsAi, aiElo: s.step.aiElo, now: s.step.now
            )
            #expect(AdaptationFixtures.Facts(facts) == s.facts, "step \(i) \(s.step.game)")
            #expect(try canonicalJSON(JSONEncoder().encode(model)) == canonicalJSON(s.json), "step \(i) \(s.step.game)")
        }
        #expect(model.features.games == fx.replay.steps.count)
        #expect(model.openings.count == 12) // 22 distinct book lines + the crafted games, capped
        #expect(model.openings == model.openings.sorted { $0.count > $1.count })
        #expect(model.wins + model.losses + model.draws == fx.replay.steps.count)

        // What the TS app persists under chess.playerModel …
        let stored = try JSONDecoder().decode(PlayerModel.self, from: Data(fx.replay.storedWithoutAdaptation.utf8))
        #expect(stored == model)
        #expect(stored.lastAdaptation == nil)
        #expect(try canonicalJSON(JSONEncoder().encode(stored)) == canonicalJSON(fx.replay.storedWithoutAdaptation))
        // … and once the adaptation notes of a game were attached.
        let withNotes = try JSONDecoder().decode(PlayerModel.self, from: Data(fx.replay.storedWithAdaptation.utf8))
        #expect(withNotes.lastAdaptation == fx.plans[0].plan.notes)
        var expected = model
        expected.lastAdaptation = fx.plans[0].plan.notes
        #expect(withNotes == expected)
        #expect(try canonicalJSON(JSONEncoder().encode(withNotes)) == canonicalJSON(fx.replay.storedWithAdaptation))
    }

    @Test("a game without aiElo or not vs the AI leaves the rating alone")
    func noRatingUpdate() throws {
        let game = try fx.build(try #require(fx.game("scholars")))
        var model = PlayerModel()
        updateModelAfterGame(&model, game: game, playerColor: .white, analysis: nil, vsAI: false, aiElo: 1000, now: fx.now)
        updateModelAfterGame(&model, game: game, playerColor: .white, analysis: nil, vsAI: true, aiElo: nil, now: fx.now)
        updateModelAfterGame(&model, game: game, playerColor: .white, analysis: nil, vsAI: true, aiElo: 0, now: fx.now)
        #expect(model.rating == 800)
        #expect(model.ratingHistory.isEmpty)
        #expect(model.wins == 3 && model.streak == 3)
        #expect(model.openings == [OpeningStat(name: "Italian Game", count: 3, asWhite: 3, wins: 3)])
    }

    @Test("loading applies newPlayerModel defaults for missing top-level keys like store.ts")
    func shallowMerge() throws {
        let m = try JSONDecoder().decode(PlayerModel.self, from: Data(#"{"version":1,"rating":1234}"#.utf8))
        var expected = PlayerModel()
        expected.rating = 1234
        #expect(m == expected)
        // Nested objects are stored whole, so they are read strictly.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlayerModel.self, from: Data(#"{"features":{"games":3}}"#.utf8))
        }
        // lastAdaptation round-trips when present.
        let notes = try JSONDecoder().decode(PlayerModel.self, from: Data(#"{"lastAdaptation":["a","b"]}"#.utf8))
        #expect(notes.lastAdaptation == ["a", "b"])
        #expect(String(decoding: try JSONEncoder().encode(notes), as: UTF8.self).contains(#""lastAdaptation":["a","b"]"#))
    }
}
