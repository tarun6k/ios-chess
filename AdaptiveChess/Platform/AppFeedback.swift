// The production `FeedbackService`: the TS `sound` and `haptic` objects side by side. The game
// controller only names events; this turns them into tones (SoundPlayer) and taps (Haptics).

import ChessServices

@MainActor
final class AppFeedback: FeedbackService {
    let sounds: SoundPlayer
    let haptics: Haptics

    init(state: AppState) {
        sounds = SoundPlayer(state: state)
        haptics = Haptics(state: state)
    }

    func play(_ sound: SoundEvent) { sounds.play(sound) }
    func trigger(_ haptic: HapticEvent) { haptics.trigger(haptic) }
}
