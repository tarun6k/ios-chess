// TS src/app/feedback.ts, `haptic`: `impact({ style })` for light / medium / heavy and
// `notification({ type })` for success / warning, every call guarded by `state.settings.haptics`.
// UIKit's generators replace the Capacitor plugin; they never throw, so there is nothing to swallow.

import ChessServices
import UIKit

@MainActor
final class Haptics {
    private let state: AppState
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    init(state: AppState) {
        self.state = state
    }

    func trigger(_ event: HapticEvent) {
        guard state.settings.haptics else { return }
        switch event {
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .heavy: heavy.impactOccurred()
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        }
    }
}
