import Foundation
import Testing
import ChessCore
@testable import ChessServices

// tests/progression.test.ts. `Date.now()` / `new Date()` are passed in as `now:` / the date argument.

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func isoDate(_ text: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return try #require(formatter.date(from: text), "bad ISO date \(text)")
}

@Suite("levels")
struct LevelTests {
    @Test("starts at level 1 needing 100 XP")
    func levelOne() {
        #expect(levelForXp(0) == LevelInfo(level: 1, into: 0, needed: 100))
    }

    @Test("advances with growing thresholds (100, 200, 300 …)")
    func thresholds() {
        #expect(levelForXp(99) == LevelInfo(level: 1, into: 99, needed: 100))
        #expect(levelForXp(100) == LevelInfo(level: 2, into: 0, needed: 200))
        #expect(levelForXp(300) == LevelInfo(level: 3, into: 0, needed: 300))
        #expect(levelForXp(599) == LevelInfo(level: 3, into: 299, needed: 300))
        #expect(levelForXp(600) == LevelInfo(level: 4, into: 0, needed: 400))
    }

    @Test("matches the TS table", arguments: ServicesFixtures.shared.levels)
    func parity(_ l: ServicesFixtures.Level) {
        #expect(levelForXp(l.xp) == LevelInfo(level: l.level, into: l.into, needed: l.needed))
    }
}

@Suite("badges")
struct BadgeTests {
    @Test("have unique ids")
    func uniqueIds() {
        let ids = badges.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("are awarded once and only the new ones are reported")
    func awardedOnce() {
        var p = PlayerProgress()
        let m = PlayerModel()
        #expect(refreshBadges(&p, m).isEmpty)
        p.counters.gamesWon = 1
        #expect(refreshBadges(&p, m).map(\.id) == ["first-win"])
        #expect(p.badges == ["first-win"])
        #expect(refreshBadges(&p, m).isEmpty)
    }

    @Test("rating badges read the player model")
    func ratingBadges() {
        var p = PlayerProgress()
        var m = PlayerModel()
        m.rating = 1250
        #expect(refreshBadges(&p, m).map(\.id) == ["rating-1200"])
        m.rating = 1650
        #expect(refreshBadges(&p, m).map(\.id) == ["rating-1600"])
    }

    @Test("counter badges fire at their thresholds")
    func counterBadges() {
        var p = PlayerProgress()
        let m = PlayerModel()
        p.counters.puzzlesSolved = 10
        p.counters.castledGames = 10
        p.dailyStreak = 7
        let ids = refreshBadges(&p, m).map(\.id).sorted()
        #expect(ids == ["castle-10", "puzzle-10", "streak-3", "streak-7"])
    }

    @Test("the table is the TS BADGES table")
    func tableParity() {
        let expected = ServicesFixtures.shared.badges
        #expect(badges.count == 14 && badges.count == expected.count)
        for (b, e) in zip(badges, expected) {
            #expect(b.id == e.id && b.title == e.title && b.description == e.description, "\(e.id)")
        }
    }

    @Test("predicates award what the TS awards", arguments: ServicesFixtures.shared.badgeScenarios)
    func scenarioParity(_ s: ServicesFixtures.BadgeScenario) {
        var p = s.progress
        var m = PlayerModel()
        m.rating = s.rating
        let fresh = refreshBadges(&p, m)
        #expect(fresh.map(\.id) == s.fresh)
        #expect(p.badges == s.badges)
        #expect(fresh.allSatisfy { badges.contains($0) })
    }

    @Test("giant-slayer is only ever granted externally")
    func giantSlayer() {
        var p = PlayerProgress()
        var m = PlayerModel()
        m.rating = 3000
        p.counters = ProgressCounters()
        p.counters.gamesWon = 999
        #expect(!refreshBadges(&p, m).map(\.id).contains("giant-slayer"))
        p.badges.append("giant-slayer")
        #expect(refreshBadges(&p, m).isEmpty)
        #expect(badges.first { $0.id == "giant-slayer" }?.earned(p, m) == true)
    }
}

@Suite("daily challenge")
struct DailyChallengeTests {
    @Test("is deterministic per calendar day and drawn from the shipped puzzles")
    func deterministic() throws {
        let a = dailyPuzzle(try isoDate("2026-03-04T10:00:00Z"))
        let b = dailyPuzzle(try isoDate("2026-03-04T23:00:00Z"))
        #expect(a == b)
        #expect(puzzles.contains(a))
    }

    @Test("varies across days")
    func varies() {
        var seen = Set<String>()
        for d in 1...31 { seen.insert(dailyPuzzle(utcDate(2026, 1, d)).id) }
        #expect(seen.count > 1)
        #expect((1...31).map { dailyPuzzle(utcDate(2026, 1, $0)).id } == ServicesFixtures.shared.january)
    }

    @Test("picks the same puzzle as the TS", arguments: ServicesFixtures.shared.daily)
    func parity(_ d: ServicesFixtures.Daily) throws {
        #expect(try isoDate(d.iso) == d.date)
        #expect(dateKey(d.date) == d.key)
        #expect(dailySeed(d.key) == d.hash)
        #expect(Int(d.hash % UInt32(puzzles.count)) == d.index)
        #expect(dailyPuzzle(d.date) == puzzles[d.index])
        #expect(dailyPuzzle(d.date).id == d.id)
    }

    @Test("the day key is the UTC calendar day")
    func utcKey() {
        #expect(dateKey(utcDate(2026, 6, 30, hour: 23, minute: 59, second: 59)) == "2026-06-30")
        #expect(dateKey(utcDate(2026, 7, 1)) == "2026-07-01")
        #expect(dateKey(Date(timeIntervalSince1970: 0)) == "1970-01-01")
        #expect(dateKey(utcDate(2024, 2, 29, hour: 12)) == "2024-02-29")
        #expect(dateKey(Date(timeIntervalSince1970: 1_767_225_599.999)) == "2025-12-31")
        #expect(dateKey(Date(timeIntervalSince1970: 1_767_225_600)) == "2026-01-01")
    }

    @Test("the seed wraps like `>>> 0`")
    func seedWraps() {
        #expect(dailySeed("") == 0)
        #expect(dailySeed("a") == 97)
        #expect(dailySeed("ab") == 97 * 31 + 98)
        // 10 characters of digits and dashes overflow 32 bits: the fixture hashes are the wrapped values.
        #expect(dailySeed("2026-01-01") == 1_161_665_730)
    }

    @Test("builds a streak on consecutive days and resets after a gap")
    func streak() throws {
        var p = PlayerProgress()

        var now = try isoDate("2026-05-01T12:00:00Z")
        #expect(!isDailyDone(p, now: now))
        completeDaily(&p, now: now)
        #expect(p.dailyStreak == 1)
        #expect(p.lastDailyDate == "2026-05-01")
        #expect(isDailyDone(p, now: now))

        completeDaily(&p, now: now) // same day again is a no-op
        #expect(p.dailyStreak == 1)

        now = try isoDate("2026-05-02T12:00:00Z")
        #expect(!isDailyDone(p, now: now))
        completeDaily(&p, now: now)
        #expect(p.dailyStreak == 2)

        now = try isoDate("2026-05-04T12:00:00Z") // skipped the 3rd
        completeDaily(&p, now: now)
        #expect(p.dailyStreak == 1)
    }

    @Test("yesterday is exactly 86 400 000 ms earlier, across month ends")
    func yesterdayAcrossMonth() throws {
        var p = PlayerProgress()
        completeDaily(&p, now: try isoDate("2026-02-28T23:59:59Z"))
        completeDaily(&p, now: try isoDate("2026-03-01T00:00:00Z"))
        #expect(p.dailyStreak == 2 && p.lastDailyDate == "2026-03-01")
        completeDaily(&p, now: try isoDate("2026-03-02T23:59:59Z"))
        #expect(p.dailyStreak == 3)
    }
}

@Suite("offerChallenges")
struct OfferChallengesTests {
    @Test("falls back to the first unfinished constraint game when nothing is targetable")
    func fallback() {
        let offers = offerChallenges(PlayerModel(), PlayerProgress(), lastGameWon: nil)
        #expect(offers.count == 1)
        #expect(offers[0].kind == .constraint)
        #expect(offers[0].constraintId == constraints[0].id)
    }

    @Test("targets the top weakness with a set of shipped puzzles")
    func targetsWeakness() throws {
        var m = PlayerModel()
        m.weaknesses[.hangingPieces] = 3
        let set = try #require(offerChallenges(m, PlayerProgress(), lastGameWon: nil).first { $0.kind == .puzzleSet })
        let ids = try #require(set.puzzleIds)
        #expect(!ids.isEmpty)
        for id in ids { #expect(puzzles.contains { $0.id == id }) }
        #expect(set.xp == ids.count * 10)
        #expect(set.detail.contains("leaving pieces undefended"))
    }

    @Test("prescribes the first unfinished drill for an endgame weakness")
    func endgameDrill() {
        var m = PlayerModel()
        m.weaknesses[.endgame] = 2
        var p = PlayerProgress()
        p.completedDrills.append(drills[0].id)
        let drill = offerChallenges(m, p, lastGameWon: nil).first { $0.kind == .drill }
        #expect(drill?.drillId == drills[1].id)
        #expect(drill?.xp == drills[1].xp)
    }

    @Test("offers a timed blitz rematch after a real game, worded by the outcome")
    func rematch() throws {
        let win = try #require(offerChallenges(PlayerModel(), PlayerProgress(), lastGameWon: true).first { $0.kind == .rematchBlitz })
        let loss = try #require(offerChallenges(PlayerModel(), PlayerProgress(), lastGameWon: false).first { $0.kind == .rematchBlitz })
        #expect(win.title == "Prove it")
        #expect(loss.title == "Redemption")
        #expect(win.timed == true)
    }

    @Test("never offers more than three and skips completed constraints")
    func atMostThree() {
        var m = PlayerModel()
        m.weaknesses[.hangingPieces] = 3
        m.weaknesses[.backRank] = 2
        var p = PlayerProgress()
        p.completedConstraints.append(constraints[0].id)
        let offers = offerChallenges(m, p, lastGameWon: true)
        #expect(offers.count <= 3)
        #expect(offers.filter { $0.kind == .puzzleSet }.count == 2)
        #expect(!offers.compactMap(\.constraintId).contains(constraints[0].id))

        let onlyConstraint = offerChallenges(PlayerModel(), p, lastGameWon: nil)
        #expect(onlyConstraint[0].constraintId == constraints[1].id)
    }

    @Test("produces the TS offers, byte for byte", arguments: ServicesFixtures.shared.offerScenarios)
    func parity(_ s: ServicesFixtures.OfferScenario) throws {
        var m = PlayerModel()
        for (key, count) in s.weaknesses {
            m.weaknesses[try #require(WeaknessKey(rawValue: key))] = count
        }
        var p = PlayerProgress()
        p.completedDrills = s.completedDrills
        p.completedConstraints = s.completedConstraints
        let offers = offerChallenges(m, p, lastGameWon: s.lastGameWon)
        #expect(offers == s.offers)

        // Same JSON as the TS objects (optional fields omitted, not null).
        let raw = try ServicesFixtures.rawObjects()
        let scenarios = try #require(raw["offerScenarios"] as? [[String: Any]])
        let expected = try #require(scenarios.first { $0["name"] as? String == s.name }?["offers"])
        #expect(try canonicalJSON(encoding: offers) == canonicalJSON(expected))
    }

    @Test("weakness tables are the TS tables")
    func tables() {
        #expect(weaknessPuzzles(.hangingPieces) == ["t-freequeen", "t-snipe", "d-qsave"])
        #expect(weaknessPuzzles(.missedTactics) == ["t-fork", "t-pin", "t-promo"])
        #expect(weaknessPuzzles(.backRank) == ["m1-backrank", "m1-deflect", "m2-ladder"])
        #expect(weaknessPuzzles(.endgame) == [] && weaknessPuzzles(.opening) == [])
        #expect(weaknessPuzzles(.kingSafety) == ["m1-backrank", "m2-boxin", "m2-qr"])
        for key in WeaknessKey.allCases {
            for id in weaknessPuzzles(key) { #expect(puzzles.contains { $0.id == id }, "\(key.rawValue): \(id)") }
        }
        #expect(WeaknessKey.allCases.map(weaknessLabel) == [
            "leaving pieces undefended", "missing tactical shots", "back-rank mates",
            "endgame technique", "the opening phase", "king safety",
        ])
    }
}

@Suite("PlayerProgress JSON")
struct ProgressCodableTests {
    @Test("a fresh record encodes like newProgress()")
    func fresh() throws {
        let f = ServicesFixtures.shared
        #expect(try canonicalJSON(encoding: PlayerProgress()) == canonicalJSON(f.blob("chess.progress.fresh")))
        #expect(try JSONDecoder().decode(PlayerProgress.self, from: Data(f.blob("chess.progress.fresh").utf8)) == PlayerProgress())
    }

    @Test("a full record round-trips unchanged")
    func full() throws {
        let blob = try ServicesFixtures.shared.blob("chess.progress")
        let p = try JSONDecoder().decode(PlayerProgress.self, from: Data(blob.utf8))
        #expect(p.xp == 250 && p.badges == ["first-win", "first-mate"] && p.solvedPuzzles == ["m1-corner", "t-fork"])
        #expect(p.completedDrills == ["kp-vs-k"] && p.dailyStreak == 2 && p.lastDailyDate == "2026-09-25")
        #expect(p.counters.gamesPlayed == 7 && p.counters.gamesWon == 3 && p.counters.hintsUsed == 4)
        #expect(try canonicalJSON(encoding: p) == canonicalJSON(blob))
    }

    @Test("an older record is merged over the defaults and re-saved in full")
    func old() throws {
        let blob = try ServicesFixtures.shared.blob("chess.progress.old")
        let p = try JSONDecoder().decode(PlayerProgress.self, from: Data(blob.utf8))
        var expected = PlayerProgress()
        expected.xp = 120
        expected.badges = ["first-win"]
        expected.counters.gamesPlayed = 3
        #expect(p == expected)
        #expect(p.counters.hintsUsed == 0 && p.completedDrills.isEmpty && p.lastDailyDate == nil)
        #expect(try canonicalJSON(encoding: p) == canonicalJSON(encoding: expected))
        #expect(try canonicalJSON(encoding: p).contains("\"lastDailyDate\":null"))
    }

    @Test("OfferedChallenge omits absent optionals and keeps present ones")
    func offerEncoding() throws {
        let drill = OfferedChallenge(id: "offer-drill-kp-vs-k", kind: .drill, title: "Endgame clinic", detail: "d", drillId: "kp-vs-k", xp: 30)
        #expect(try canonicalJSON(encoding: drill) == #"{"detail":"d","drillId":"kp-vs-k","id":"offer-drill-kp-vs-k","kind":"drill","title":"Endgame clinic","xp":30}"#)
        let rematch = OfferedChallenge(id: "offer-rematch", kind: .rematchBlitz, title: "Prove it", detail: "d", timed: true, xp: 25)
        #expect(try canonicalJSON(encoding: rematch) == #"{"detail":"d","id":"offer-rematch","kind":"rematch-blitz","timed":true,"title":"Prove it","xp":25}"#)
        #expect(OfferKind.allCases.map(\.rawValue) == ["puzzle-set", "rematch-blitz", "drill", "constraint"])
    }
}
