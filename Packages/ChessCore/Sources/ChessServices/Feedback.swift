// TS src/app/feedback.ts: the `sound` and `haptic` objects the controller calls. The controller only
// names the events; the app target renders them (Platform/SoundPlayer.swift synthesises the tones with
// AVAudioEngine, Platform/Haptics.swift drives UIKit's feedback generators) and honours the
// `sounds` / `haptics` settings there, like `audio()` returning null and `impact()` bailing out in the TS.

/// `sound.move()`, `sound.capture()`, … — one case per tone in feedback.ts.
public enum SoundEvent: String, Hashable, Sendable, CaseIterable {
    case move
    case capture
    case check
    case castle
    case promote
    case gameWin
    case gameLoss
    case gameDraw
    case lowTime
    case error
}

/// `haptic.light()` / `.medium()` / `.heavy()` (impact) and `.success()` / `.warning()` (notification).
public enum HapticEvent: String, Hashable, Sendable, CaseIterable {
    case light
    case medium
    case heavy
    case success
    case warning
}

@MainActor
public protocol FeedbackService: AnyObject {
    func play(_ sound: SoundEvent)
    func trigger(_ haptic: HapticEvent)
}

/// The no-op service (the mocked `sound` / `haptic` of tests/controller.test.ts); also handy for previews.
@MainActor
public final class SilentFeedback: FeedbackService {
    public init() {}
    public func play(_ sound: SoundEvent) {}
    public func trigger(_ haptic: HapticEvent) {}
}
