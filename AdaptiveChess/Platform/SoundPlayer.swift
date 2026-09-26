// TS src/app/feedback.ts, `sound`: the WebAudio tone synth. Every `tone(freq, dur, type, gain, when)`
// call becomes a `Voice` rendered by one AVAudioSourceNode: oscillator of the given waveform, gain set
// at `t = currentTime + when`, exponential ramp to 0.0005 over `dur` (`v(t) = gain · (0.0005 / gain)^(t / dur)`,
// held at 0.0005 afterwards) and stop at `t + dur + 0.02`. The frequencies, durations, waveforms, gains
// and offsets below are the TS table verbatim. `audio()` returns nil while sounds are switched off,
// creates the engine lazily and restarts it when it is not running (the TS `resume()` of a suspended
// context). The session category is `.ambient` so the user's own music keeps playing underneath.

import AVFoundation
import ChessServices
import os

/// One synthesised tone, in sample units. Read and mutated on the audio thread only.
nonisolated struct Voice: Sendable {
    enum Wave: Sendable {
        case sine
        case triangle
        case square
    }

    let frequency: Double
    let wave: Wave
    let gain: Double
    /// `osc.start(t)`
    let startSample: Int64
    /// `dur`: the ramp `gain → 0.0005` runs over this many seconds
    let rampSeconds: Double
    /// `osc.stop(t + dur + 0.02)`
    let endSample: Int64
    /// oscillator phase in cycles, 0 ≤ phase < 1
    var phase: Double = 0
}

/// The voices currently sounding, shared between the main actor (which adds tones) and the audio
/// render thread (which mixes them) under an unfair lock; a handful of voices at most, so the
/// critical section is a few microseconds. `nonisolated`: the app target defaults to main-actor isolation,
/// and this is called from the render thread.
nonisolated final class VoiceBank: Sendable {
    private struct State {
        var voices: [Voice] = []
        /// samples rendered so far — `ac.currentTime` in sample units
        var sample: Int64 = 0
    }

    let sampleRate: Double
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// `ac.currentTime`, in samples.
    var currentSample: Int64 { state.withLock { $0.sample } }

    func add(_ voice: Voice) {
        state.withLock { $0.voices.append(voice) }
    }

    /// Mixes `frames` mono samples into `out`; returns true when nothing was sounding (`isSilence`).
    func render(into out: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        state.withLockUnchecked { s in
            if s.voices.isEmpty {
                out.update(repeating: 0, count: frames)
                s.sample += Int64(frames)
                return true
            }
            for i in 0..<frames {
                let t = s.sample + Int64(i)
                var sum = 0.0
                var v = 0
                while v < s.voices.count {
                    if t >= s.voices[v].endSample {
                        s.voices.remove(at: v)
                        continue
                    }
                    if t >= s.voices[v].startSample {
                        let voice = s.voices[v]
                        let elapsed = Double(t - voice.startSample) / sampleRate
                        // gain.setValueAtTime(gain, t); gain.exponentialRampToValueAtTime(0.0005, t + dur)
                        let envelope = elapsed < voice.rampSeconds
                            ? voice.gain * pow(0.0005 / voice.gain, elapsed / voice.rampSeconds)
                            : 0.0005
                        sum += envelope * Self.sample(voice.wave, at: voice.phase)
                        var phase = voice.phase + voice.frequency / sampleRate
                        if phase >= 1 { phase -= 1 }
                        s.voices[v].phase = phase
                    }
                    v += 1
                }
                out[i] = Float(max(-1, min(1, sum)))
            }
            s.sample += Int64(frames)
            return false
        }
    }

    /// OscillatorNode waveforms at `phase` cycles: sine, triangle (rising through 0 at phase 0) and square.
    private static func sample(_ wave: Voice.Wave, at phase: Double) -> Double {
        switch wave {
        case .sine:
            return sin(2 * Double.pi * phase)
        case .triangle:
            if phase < 0.25 { return 4 * phase }
            if phase < 0.75 { return 2 - 4 * phase }
            return 4 * phase - 4
        case .square:
            return phase < 0.5 ? 1 : -1
        }
    }
}

@MainActor
final class SoundPlayer {
    private let state: AppState
    private var engine: AVAudioEngine? = nil
    private var bank: VoiceBank? = nil
    private var setUpFailed = false

    init(state: AppState) {
        self.state = state
    }

    /// TS `audio()`: nil when sounds are off or the engine cannot run; otherwise the running bank.
    private func audio() -> VoiceBank? {
        guard state.settings.sounds else { return nil }
        if engine == nil && !setUpFailed { setUp() }
        guard let engine, let bank else { return nil }
        if !engine.isRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
            } catch {
                return nil
            }
        }
        return bank
    }

    private func setUp() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let engine = AVAudioEngine()
            var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            if sampleRate <= 0 { sampleRate = 44_100 }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                setUpFailed = true
                return
            }
            let bank = VoiceBank(sampleRate: sampleRate)
            let source = AVAudioSourceNode(format: format) { @Sendable isSilence, _, frameCount, audioBufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard buffers.count > 0, let data = buffers[0].mData else { return noErr }
                let silent = bank.render(into: data.assumingMemoryBound(to: Float.self), frames: Int(frameCount))
                isSilence.pointee = ObjCBool(silent)
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            try engine.start()
            self.engine = engine
            self.bank = bank
        } catch {
            setUpFailed = true
            engine = nil
            bank = nil
        }
    }

    /// TS `tone(freq, dur, type, gain = 0.12, when = 0)` with `t = ac.currentTime + when`.
    private func tone(_ ac: VoiceBank, at now: Int64, _ freq: Double, _ dur: Double, _ wave: Voice.Wave,
                      _ gain: Double = 0.12, _ when: Double = 0) {
        let t = now + Int64((when * ac.sampleRate).rounded())
        ac.add(Voice(frequency: freq, wave: wave, gain: gain, startSample: t, rampSeconds: dur,
                     endSample: t + Int64(((dur + 0.02) * ac.sampleRate).rounded())))
    }

    func play(_ event: SoundEvent) {
        guard let ac = audio() else { return }
        let now = ac.currentSample
        switch event {
        case .move:
            tone(ac, at: now, 320, 0.07, .sine, 0.1)
        case .capture:
            tone(ac, at: now, 180, 0.09, .triangle, 0.16)
            tone(ac, at: now, 120, 0.1, .sine, 0.1, 0.02)
        case .check:
            tone(ac, at: now, 660, 0.1, .sine, 0.12)
            tone(ac, at: now, 880, 0.12, .sine, 0.1, 0.09)
        case .castle:
            tone(ac, at: now, 320, 0.06, .sine, 0.1)
            tone(ac, at: now, 400, 0.06, .sine, 0.1, 0.08)
        case .promote:
            tone(ac, at: now, 520, 0.08, .sine, 0.1)
            tone(ac, at: now, 660, 0.08, .sine, 0.1, 0.07)
            tone(ac, at: now, 780, 0.12, .sine, 0.1, 0.14)
        case .gameWin:
            tone(ac, at: now, 392, 0.12, .sine, 0.12)
            tone(ac, at: now, 494, 0.12, .sine, 0.12, 0.12)
            tone(ac, at: now, 587, 0.22, .sine, 0.12, 0.24)
        case .gameLoss:
            tone(ac, at: now, 330, 0.16, .sine, 0.12)
            tone(ac, at: now, 262, 0.28, .sine, 0.12, 0.16)
        case .gameDraw:
            tone(ac, at: now, 392, 0.14, .sine, 0.1)
            tone(ac, at: now, 392, 0.18, .sine, 0.08, 0.18)
        case .lowTime:
            tone(ac, at: now, 880, 0.06, .square, 0.07)
            tone(ac, at: now, 880, 0.06, .square, 0.07, 0.12)
        case .error:
            tone(ac, at: now, 160, 0.1, .square, 0.06)
        }
    }
}
