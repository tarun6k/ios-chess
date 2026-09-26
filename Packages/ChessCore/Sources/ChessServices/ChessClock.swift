// TS src/app/clock.ts: the time presets, `customTimeControl`, the Fischer-increment `ChessClock` and
// `formatClock` (`TimeControl` itself is in TimeControl.swift since Phase 2). The TS clock reads
// `Date.now()` and ticks with `setInterval(…, 100)`; here both come from an injectable
// `ClockTimeSource` — `ContinuousClockTimeSource` in the app, `ManualTimeSource` in tests.

import ChessCore

/// TS `TIME_PRESETS`.
public let timePresets: [TimeControl] = [
    TimeControl(name: "Bullet 1+0", baseMs: 60_000, incrementMs: 0),
    TimeControl(name: "Blitz 3+2", baseMs: 180_000, incrementMs: 2_000),
    TimeControl(name: "Rapid 10+0", baseMs: 600_000, incrementMs: 0),
    TimeControl(name: "Rapid 15+10", baseMs: 900_000, incrementMs: 10_000),
    TimeControl(name: "Classical 30+0", baseMs: 1_800_000, incrementMs: 0),
]

/// JS `Math.round`: the nearest integer, halves towards +∞ (Swift's `rounded()` takes them away from zero).
func jsRound(_ x: Double) -> Double {
    let floor = x.rounded(.down)
    return x - floor >= 0.5 ? floor + 1 : floor
}

/// Base minutes clamped to 1…120 and increment seconds to 0…60, both rounded like `Math.round`.
public func customTimeControl(baseMin: Double, incSec: Double) -> TimeControl {
    let b = Int(max(1, min(120, jsRound(baseMin))))
    let i = Int(max(0, min(60, jsRound(incSec))))
    return TimeControl(name: "Custom \(b)+\(i)", baseMs: b * 60_000, incrementMs: i * 1000)
}

/// TS `Date.now()` and `setInterval`: the wall clock and the interval timer a `ChessClock` runs on.
@MainActor
public protocol ClockTimeSource: AnyObject {
    /// Milliseconds on a monotonic scale; only differences are used.
    var nowMs: Int { get }
    /// Calls `tick` every `intervalMs` milliseconds until the returned timer is cancelled.
    func schedule(intervalMs: Int, _ tick: @escaping @MainActor () -> Void) -> ClockTimer
}

/// A repeating timer handle (`clearInterval`).
@MainActor
public final class ClockTimer {
    private var onCancel: (@MainActor () -> Void)?

    public init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// The production time source: `ContinuousClock` (keeps counting while the device sleeps, like
/// `Date.now()`) and a main-actor `Task` that sleeps `intervalMs` between ticks.
@MainActor
public final class ContinuousClockTimeSource: ClockTimeSource {
    private let origin = ContinuousClock.now

    public init() {}

    public var nowMs: Int {
        let (seconds, attoseconds) = origin.duration(to: .now).components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    public func schedule(intervalMs: Int, _ tick: @escaping @MainActor () -> Void) -> ClockTimer {
        let task = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(intervalMs)) } catch { return }
                if Task.isCancelled { return }
                tick()
            }
        }
        return ClockTimer { task.cancel() }
    }
}

/// A hand-driven time source for tests and previews (vitest's fake timers): `advance(ms:)` moves the
/// clock and fires every due timer in order, setting `nowMs` to the timer's due time before its callback
/// runs, exactly like `vi.advanceTimersByTime`.
@MainActor
public final class ManualTimeSource: ClockTimeSource {
    private final class Entry {
        let intervalMs: Int
        var dueMs: Int
        let tick: @MainActor () -> Void

        init(intervalMs: Int, dueMs: Int, tick: @escaping @MainActor () -> Void) {
            self.intervalMs = intervalMs
            self.dueMs = dueMs
            self.tick = tick
        }
    }

    public private(set) var nowMs: Int
    private var timers: [Entry] = []

    public init(nowMs: Int = 0) {
        self.nowMs = nowMs
    }

    /// Number of live timers (0 once every clock is paused or disposed).
    public var scheduledTimerCount: Int { timers.count }

    public func schedule(intervalMs: Int, _ tick: @escaping @MainActor () -> Void) -> ClockTimer {
        let entry = Entry(intervalMs: intervalMs, dueMs: nowMs + intervalMs, tick: tick)
        timers.append(entry)
        return ClockTimer { [weak self] in
            self?.timers.removeAll { $0 === entry }
        }
    }

    /// Moves time forward by `ms`, firing due timers in due-time order (registration order on ties).
    public func advance(ms: Int) {
        let target = nowMs + ms
        while let next = timers.min(by: { $0.dueMs < $1.dueMs }), next.dueMs <= target {
            nowMs = next.dueMs
            next.dueMs += next.intervalMs
            next.tick()
        }
        nowMs = target
    }
}

/// Fischer-increment chess clock. Wall-clock based (robust to throttled timers); ticks a callback for
/// display, fires once on flag fall and low-time warning. Like the TS `setInterval`, a running clock
/// is kept alive by its timer: call `pause()` / `dispose()` before dropping it.
@MainActor
public final class ChessClock {
    /// Milliseconds left for white and black (TS `remaining: [number, number]`).
    public var remaining: ClockRemaining
    public let increment: Int
    public private(set) var active: PieceColor? = nil
    private var lastStamp = 0
    private var timer: ClockTimer? = nil
    private var lowWarned = [false, false]
    private let time: any ClockTimeSource

    public var onTick: (() -> Void)? = nil
    public var onFlag: ((PieceColor) -> Void)? = nil
    public var onLowTime: ((PieceColor) -> Void)? = nil

    public init(_ tc: TimeControl, timeSource: any ClockTimeSource = ContinuousClockTimeSource()) {
        remaining = ClockRemaining(white: tc.whiteBaseMs ?? tc.baseMs, black: tc.blackBaseMs ?? tc.baseMs)
        increment = tc.incrementMs
        time = timeSource
    }

    /// Start (or switch to) `color`'s clock; adds increment to the side that just moved.
    public func press(_ mover: PieceColor) {
        syncElapsed()
        if active == mover {
            remaining[mover] += increment
        }
        active = mover.opponent
        ensureTimer()
    }

    public func start(_ color: PieceColor) {
        syncElapsed()
        active = color
        ensureTimer()
    }

    public func pause() {
        syncElapsed()
        active = nil
        stopTimer()
    }

    public func stop() { pause() }

    private func ensureTimer() {
        lastStamp = time.nowMs
        if timer != nil { return }
        timer = time.schedule(intervalMs: 100) {
            self.syncElapsed()
            self.onTick?()
        }
    }

    private func stopTimer() {
        if let timer {
            timer.cancel()
            self.timer = nil
        }
    }

    private func syncElapsed() {
        let now = time.nowMs
        if let c = active {
            remaining[c] = max(0, remaining[c] - (now - lastStamp))
            if remaining[c] <= 20_000 && !lowWarned[c.rawValue] && remaining[c] > 0 {
                lowWarned[c.rawValue] = true
                onLowTime?(c)
            }
            if remaining[c] == 0 {
                let flagged = c
                active = nil
                stopTimer()
                onFlag?(flagged)
            }
        }
        lastStamp = now
    }

    public func dispose() { stopTimer() }
}

/// `h:mm:ss` from one hour, `m:ss` (partial seconds rounded up) above 20 s, `m:ss.t` tenths below.
public func formatClock(_ ms: Int) -> String {
    let t = Int((Double(ms) / 1000).rounded(.up))
    if t >= 3600 {
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return "\(h):\(pad2(m)):\(pad2(s))"
    }
    if ms < 20_000 {
        // tenths under 20s
        let whole = ms / 1000, tenth = (ms % 1000) / 100
        return "\(whole / 60):\(pad2(whole % 60)).\(tenth)"
    }
    return "\(t / 60):\(pad2(t % 60))"
}

/// `String(n).padStart(2, '0')`.
private func pad2(_ n: Int) -> String {
    n < 10 ? "0\(n)" : "\(n)"
}
