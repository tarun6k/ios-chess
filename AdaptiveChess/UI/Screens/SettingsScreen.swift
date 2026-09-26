// src/ui/settingsScreen.ts: board & feedback preferences from the spec, in the design language.
// Every change is written straight to the store (`persist.settings()`).

import ChessServices
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppBoot.self) private var boot

    var body: some View {
        ScreenPage { vw in
            PageHeader(title: "Settings")
            PageColumn(viewportWidth: vw) {
                Card(style: .inline) {
                    SectionLabel("Board")
                    toggleRow("Coordinates", "Show file and rank labels", \.coordinates)
                    DividerLine()
                    settingRow("Board orientation", "Auto flips for pass-and-play") {
                        SegmentedControl(
                            options: [.init(BoardFlip.auto, "Auto"), .init(BoardFlip.white, "White"), .init(BoardFlip.black, "Black")],
                            selection: binding(\.boardFlip)
                        )
                        .accessibilityIdentifier("setting-boardFlip")
                    }
                }
                Card(style: .inline) {
                    SectionLabel("Play")
                    toggleRow("Auto-queen", "Skip the promotion picker, always promote to queen", \.autoQueen)
                    DividerLine()
                    toggleRow("Takebacks", "Undo in casual untimed games (never in challenges)", \.takebacks)
                }
                Card(style: .inline) {
                    SectionLabel("Feedback")
                    toggleRow("Sounds", "Move, capture, check and game-end sounds", \.sounds)
                    DividerLine()
                    toggleRow("Haptics", "Vibration on moves and important moments", \.haptics)
                    DividerLine()
                    toggleRow("Animations", "Subtle piece movement animation", \.animations)
                }
                Card(style: .inline) {
                    SectionLabel("About")
                    Text("Adaptive Chess — fully offline. The AI models your style on-device; nothing ever leaves your phone.")
                        .textStyle(.inline(13, opacity: 0.8))
                }
            }
        }
    }

    /// `set(key, value)`: write the setting and persist.
    private func binding<V: Hashable & Sendable>(_ key: WritableKeyPath<Settings, V>) -> Binding<V> {
        Binding(
            get: { boot.state.settings[keyPath: key] },
            set: { value in
                boot.state.settings[keyPath: key] = value
                boot.state.persist(.settings)
            }
        )
    }

    /// `toggleRow(label, hint, key)`: the label + hint on the left, an On / Off segment on the right.
    private func toggleRow(_ label: String, _ hint: String, _ key: WritableKeyPath<Settings, Bool>) -> some View {
        settingRow(label, hint) {
            SegmentedControl(options: [.init(true, "On"), .init(false, "Off")], selection: binding(key))
                .accessibilityIdentifier("setting-\(label)")
        }
    }

    private func settingRow<Control: View>(_ label: String, _ hint: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).textStyle(.inline(14))
                Text(hint).textStyle(.inline(12, color: Theme.neutral500))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
    }
}
