// src/ui/loginScreen.ts: asks for a player name on first launch — serif heading, surface input,
// filled accent button and a quiet "continue as guest" escape hatch. The name (or the guest
// choice) is persisted through the store, so this screen only ever shows once.

import ChessServices
import SwiftUI

struct LoginScreen: View {
    @Environment(AppBoot.self) private var boot

    @State private var name = ""
    @State private var hint = " "
    @State private var hintVisible = false
    @State private var appeared = false
    @FocusState private var inputFocused: Bool

    private var hasText: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GeometryReader { proxy in
            // `min-height: 100vh` — the safe-area viewport, so the bottom block sits above the
            // home indicator (and above the keyboard once it appears).
            let viewportHeight = proxy.size.height
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    top(fullHeight: fullHeight)
                    nameBlock
                    Spacer(minLength: 0)
                    bottom
                }
                .frame(width: min(420, proxy.size.width), alignment: .leading)
                .frame(minHeight: viewportHeight)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { appeared = true }
        .task {
            // Focus after the mount so the fade-in has begun and iOS shows the caret.
            try? await Task.sleep(for: .milliseconds(350))
            inputFocused = true
        }
    }

    // MARK: blocks

    /// `padding-top: clamp(48px, 12vh, 96px); animation: fade-up .5s ease both`
    private func top(fullHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What should we call you?")
                .textStyle(.loginTitle)
            Text("Used on the scoresheet. Stored on this device only.")
                .textStyle(.loginLead)
                .padding(.top, Theme.Space.s3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, cssClamp(48, 0.12 * fullHeight, 96))
        .padding(.horizontal, Theme.Space.s6)
        .fadeUp(appeared, delay: 0)
    }

    /// `padding-top: space-8; gap: space-2; animation: fade-up .5s .08s ease both`
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            SectionLabel("Player name")
            TextField(text: $name, prompt: Text("Enter your name").foregroundStyle(InputChrome.placeholderColor)) {
                Text("Enter your name")
            }
                .focused($inputFocused)
                .textContentType(.name)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(submit)
                .onChange(of: name) { _, value in
                    // maxlength="40"
                    if value.count > 40 { name = String(value.prefix(40)) }
                    hintVisible = false
                }
                .modifier(InputChrome(focused: inputFocused, style: .loginInput,
                                      vertical: Theme.Space.s3, horizontal: Theme.Space.s3,
                                      background: Theme.surface))
                .accessibilityLabel("Player name")
                .accessibilityIdentifier("login-name")
            Text(hint)
                .textStyle(.loginHint)
                .foregroundStyle(hintVisible ? Theme.text.opacity(0.55) : .clear)
                .frame(minHeight: 1.4 * 12.5, alignment: .leading)
                .accessibilityHidden(!hintVisible)
        }
        .padding(.top, Theme.Space.s8)
        .padding(.horizontal, Theme.Space.s6)
        .fadeUp(appeared, delay: 0.08)
    }

    /// `gap: space-4; padding-bottom: space-8; animation: fade-up .5s .16s ease both`
    private var bottom: some View {
        VStack(spacing: Theme.Space.s4) {
            Button("Start playing", action: submit)
                .buttonStyle(LoginButtonStyle(armed: hasText))
                .accessibilityIdentifier("login-start")
            Button(action: asGuest) {
                Text("Continue as guest")
                    .textStyle(.loginLink)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("login-guest")
        }
        .padding(.bottom, Theme.Space.s8)
        .padding(.horizontal, Theme.Space.s6)
        .frame(maxWidth: .infinity)
        .fadeUp(appeared, delay: 0.16)
    }

    // MARK: actions

    private func showHint(_ text: String) {
        hint = text
        hintVisible = true
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            showHint("Enter a name, or continue as guest.")
            return
        }
        showHint("Setting up your board, \(trimmed)…")
        boot.state.playerName = trimmed
        boot.state.guest = false
        boot.state.persist(.playerName)
        boot.state.persist(.guest)
        inputFocused = false // dismiss the keyboard before leaving, so its scroll compensation unwinds
        boot.navigate(.home)
    }

    private func asGuest() {
        showHint("Starting a guest game…")
        boot.state.playerName = nil
        boot.state.guest = true
        boot.state.persist(.playerName)
        boot.state.persist(.guest)
        inputFocused = false
        boot.navigate(.home)
    }
}

/// The inline-styled "Start playing" button: min-height 48, padding space-3, radius 4, accent
/// background (accent-600 and 1px down while pressed with a name typed), #fdfcfb 15px/500 text,
/// shadow-sm, opacity 0.55 until a name is typed.
private struct LoginButtonStyle: ButtonStyle {
    let armed: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && armed
        configuration.label
            .textStyle(.loginButton)
            .padding(Theme.Space.s3)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(pressed ? Theme.accent600 : Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .compositingGroup()
            .themeShadow(.sm)
            .opacity(armed ? 1 : 0.55)
            .offset(y: pressed ? 1 : 0)
            .padding(.top, Theme.Space.s2) // .btn-block margin-top
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2), value: armed)
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: pressed)
            .contentShape(Rectangle())
    }
}

private extension View {
    /// `@keyframes fade-up { from { opacity: 0; transform: translateY(6px) } }`, `.5s ease` with a delay.
    func fadeUp(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.5).delay(delay), value: appeared)
    }
}
