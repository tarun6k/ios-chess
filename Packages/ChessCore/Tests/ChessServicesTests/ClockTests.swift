import Foundation
import Testing
import ChessCore
@testable import ChessServices

// tests/clock.test.ts. The TS runs on vitest's fake timers frozen at 2026-01-01T00:00:00Z; here the
// clock runs on a `ManualTimeSource` started at that instant's epoch milliseconds.

@MainActor
@Suite("ChessClock")
struct ChessClockTests {
    static let epoch2026 = 1_767_225_600_000

    func makeTime() -> ManualTimeSource { ManualTimeSource(nowMs: Self.epoch2026) }

    @Test("initialises from the control, honouring per-side overrides")
    func initialises() {
        let c = ChessClock(TimeControl(name: "t", baseMs: 60_000, incrementMs: 1000, blackBaseMs: 30_000), timeSource: makeTime())
        #expect(c.remaining == ClockRemaining(white: 60_000, black: 30_000))
        #expect(c.increment == 1000)
        #expect(c.active == nil)
    }

    @Test("start() drains only the given side, by wall-clock time")
    func startDrains() {
        let time = makeTime()
        let c = ChessClock(timePresets[1], timeSource: time) // Blitz 3+2
        c.start(.white)
        time.advance(ms: 1500)
        #expect(c.remaining[.white] == 180_000 - 1500)
        #expect(c.remaining[.black] == 180_000)
        c.dispose()
    }

    @Test("press() awards the increment to the mover and switches sides")
    func pressAwardsIncrement() {
        let time = makeTime()
        let c = ChessClock(timePresets[1], timeSource: time)
        c.start(.white)
        time.advance(ms: 5000)
        c.press(.white)
        #expect(c.remaining[.white] == 180_000 - 5000 + 2000)
        #expect(c.active == .black)
        time.advance(ms: 1000)
        #expect(c.remaining[.black] == 179_000)
        #expect(c.remaining[.white] == 177_000)
        c.dispose()
    }

    @Test("press() by the side not on move awards no increment")
    func pressByOtherSide() {
        let time = makeTime()
        let c = ChessClock(timePresets[1], timeSource: time)
        c.start(.white)
        c.press(.black)
        #expect(c.remaining[.black] == 180_000)
        #expect(c.active == .white)
        c.dispose()
    }

    @Test("pause() freezes both sides until start() is called again")
    func pauseFreezes() {
        let time = makeTime()
        let c = ChessClock(timePresets[2], timeSource: time) // Rapid 10+0
        c.start(.black)
        time.advance(ms: 2000)
        c.pause()
        time.advance(ms: 10_000)
        #expect(c.remaining[.black] == 598_000)
        #expect(c.active == nil)
        c.start(.black)
        time.advance(ms: 1000)
        #expect(c.remaining[.black] == 597_000)
        c.dispose()
    }

    @Test("ticks the display callback every 100ms while running")
    func ticksEvery100ms() {
        let time = makeTime()
        let c = ChessClock(timePresets[2], timeSource: time)
        var ticks = 0
        c.onTick = { ticks += 1 }
        c.start(.white)
        time.advance(ms: 1000)
        #expect(ticks == 10)
        c.pause()
        time.advance(ms: 1000)
        #expect(ticks == 10)
    }

    @Test("warns exactly once when a side drops to 20 seconds")
    func lowTimeOnce() {
        let time = makeTime()
        let c = ChessClock(TimeControl(name: "t", baseMs: 25_000, incrementMs: 0), timeSource: time)
        var low: [PieceColor] = []
        c.onLowTime = { low.append($0) }
        c.start(.white)
        time.advance(ms: 4900)
        #expect(low.isEmpty)
        time.advance(ms: 200)
        #expect(low == [.white])
        time.advance(ms: 3000)
        #expect(low == [.white])
        c.dispose()
    }

    @Test("flags at zero: clamps, stops the timer, fires onFlag once")
    func flagsAtZero() {
        let time = makeTime()
        let c = ChessClock(TimeControl(name: "t", baseMs: 1000, incrementMs: 0), timeSource: time)
        var flags: [PieceColor] = []
        c.onFlag = { flags.append($0) }
        c.start(.black)
        time.advance(ms: 1500)
        #expect(c.remaining[.black] == 0)
        #expect(c.active == nil)
        #expect(flags == [.black])
        time.advance(ms: 1000)
        #expect(flags == [.black])
        #expect(c.remaining[.white] == 1000)
        #expect(time.scheduledTimerCount == 0, "the interval is cleared on flag")
    }

    @Test("dispose() stops ticking")
    func disposeStops() {
        let time = makeTime()
        let c = ChessClock(timePresets[0], timeSource: time)
        var ticks = 0
        c.onTick = { ticks += 1 }
        c.start(.white)
        c.dispose()
        time.advance(ms: 1000)
        #expect(ticks == 0)
        #expect(time.scheduledTimerCount == 0)
    }

    @Test("one interval per running clock: start, press and restart never stack timers")
    func singleTimer() {
        let time = makeTime()
        let c = ChessClock(timePresets[1], timeSource: time)
        #expect(time.scheduledTimerCount == 0)
        c.start(.white)
        c.start(.white)
        c.press(.white)
        c.press(.black)
        #expect(time.scheduledTimerCount == 1)
        c.pause()
        #expect(time.scheduledTimerCount == 0)
        c.start(.black)
        #expect(time.scheduledTimerCount == 1)
        c.stop()
        #expect(time.scheduledTimerCount == 0)
    }

    @Test("a low-time warning on one side leaves the other side's warning armed")
    func lowTimePerSide() {
        let time = makeTime()
        let c = ChessClock(TimeControl(name: "t", baseMs: 20_500, incrementMs: 0), timeSource: time)
        var low: [PieceColor] = []
        c.onLowTime = { low.append($0) }
        c.start(.white)
        time.advance(ms: 600)
        c.press(.white)
        time.advance(ms: 600)
        #expect(low == [.white, .black])
        c.dispose()
    }

    @Test("the continuous time source drains by elapsed monotonic time and ticks on the main actor")
    func continuousSource() async throws {
        let clock = ContinuousClock()
        let before = clock.now
        let c = ChessClock(timePresets[2], timeSource: ContinuousClockTimeSource())
        var ticks = 0
        c.onTick = { ticks += 1 }
        c.start(.white)
        try await Task.sleep(for: .milliseconds(350))
        c.pause()
        let elapsed = before.duration(to: clock.now)
        let elapsedMs = Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        let drained = 600_000 - c.remaining[.white]
        #expect(ticks >= 1)
        #expect(drained > 0)
        #expect(drained <= elapsedMs + 2)
        #expect(c.remaining[.black] == 600_000)
        let frozen = c.remaining[.white]
        try await Task.sleep(for: .milliseconds(150))
        #expect(c.remaining[.white] == frozen, "paused: the task is cancelled and nothing drains")
    }
}

@MainActor
@Suite("ManualTimeSource")
struct ManualTimeSourceTests {
    @Test("fires due timers in due order, setting nowMs to each due time first")
    func firesInOrder() {
        let time = ManualTimeSource()
        var log: [String] = []
        let a = time.schedule(intervalMs: 100) { log.append("A\(time.nowMs)") }
        let b = time.schedule(intervalMs: 250) { log.append("B\(time.nowMs)") }
        time.advance(ms: 500)
        #expect(log == ["A100", "A200", "B250", "A300", "A400", "A500", "B500"])
        #expect(time.nowMs == 500)
        b.cancel()
        time.advance(ms: 100)
        #expect(log.last == "A600" && log.count == 8)
        a.cancel()
        a.cancel()
        time.advance(ms: 1000)
        #expect(log.count == 8 && time.nowMs == 1600)
        #expect(time.scheduledTimerCount == 0)
    }

    @Test("advancing without timers just moves the clock")
    func advanceOnly() {
        let time = ManualTimeSource(nowMs: 42)
        time.advance(ms: 8)
        #expect(time.nowMs == 50)
    }
}

@Suite("time controls")
struct TimeControlTests {
    @Test("ships five named presets")
    func presets() {
        #expect(timePresets.map(\.name) == ["Bullet 1+0", "Blitz 3+2", "Rapid 10+0", "Rapid 15+10", "Classical 30+0"])
        #expect(timePresets == ServicesFixtures.shared.presets)
    }

    @Test("builds a custom control in ms")
    func custom() {
        #expect(customTimeControl(baseMin: 3, incSec: 2) == TimeControl(name: "Custom 3+2", baseMs: 180_000, incrementMs: 2000))
    }

    @Test("clamps and rounds custom values")
    func clampsAndRounds() {
        #expect(customTimeControl(baseMin: 0, incSec: -5) == TimeControl(name: "Custom 1+0", baseMs: 60_000, incrementMs: 0))
        #expect(customTimeControl(baseMin: 500, incSec: 999) == TimeControl(name: "Custom 120+60", baseMs: 7_200_000, incrementMs: 60_000))
        #expect(customTimeControl(baseMin: 2.6, incSec: 1.4) == TimeControl(name: "Custom 3+1", baseMs: 180_000, incrementMs: 1000))
    }

    @Test("rounds halves like Math.round (towards +∞)", arguments: ServicesFixtures.shared.custom)
    func customParity(_ c: ServicesFixtures.Custom) {
        #expect(customTimeControl(baseMin: c.baseMin, incSec: c.incSec) == c.control)
    }

    @Test("jsRound")
    func rounding() {
        #expect(jsRound(2.5) == 3 && jsRound(-2.5) == -2 && jsRound(-3.5) == -3 && jsRound(0.49999) == 0 && jsRound(-0.5) == 0)
    }
}

@Suite("formatClock")
struct FormatClockTests {
    @Test("shows hours when at or above one hour")
    func hours() {
        #expect(formatClock(3_600_000) == "1:00:00")
        #expect(formatClock(5_025_000) == "1:23:45")
    }

    @Test("shows m:ss, rounding partial seconds up")
    func minutes() {
        #expect(formatClock(600_000) == "10:00")
        #expect(formatClock(59_400) == "1:00")
        #expect(formatClock(20_000) == "0:20")
    }

    @Test("shows tenths under 20 seconds")
    func tenths() {
        #expect(formatClock(19_950) == "0:19.9")
        #expect(formatClock(5_040) == "0:05.0")
        #expect(formatClock(0) == "0:00.0")
    }

    @Test("matches the TS output", arguments: ServicesFixtures.shared.format)
    func parity(_ f: ServicesFixtures.Format) {
        #expect(formatClock(f.ms) == f.text)
    }
}
