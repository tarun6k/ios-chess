// gameScreen.ts `reviewCard()` / `uciToSanAt()`: the eval bar and judgment for the reviewed ply.

import ChessCore
import ChessServices
import SwiftUI

struct ReviewCard: View {
    @Environment(AppBoot.self) private var boot

    var body: some View {
        let controller = boot.controller
        let ply = boot.playScreen.reviewPly ?? 0
        let analysis = controller.analysis
        let a: AnalyzedMove? = ply > 0 ? analysis.flatMap { ply - 1 < $0.count ? $0[ply - 1] : nil } : nil

        // eval bar: white share from cp
        let cp = a?.evalAfter ?? 0
        let share = 100 / (1 + pow(10, -Double(cp) / 400)) // logistic → %

        Card(style: .inline) {
            SectionLabel("Review")
            evalBar(share: share)
            SpaceBetween(alignment: .baseline) {
                Text(a != nil ? (cp >= 0 ? "+" : "") + jsToFixed(Double(cp) / 100, 1) : "0.0")
                    .textStyle(.inline(13, tabularNumbers: true))
                    .accessibilityIdentifier("play-review-eval")
            } trailing: {
                if let a {
                    Text(a.judgment == .best ? "Best move" : a.judgment == .good ? "Good" : a.judgment.rawValue)
                        .textStyle(.inline(13, color: JudgmentStyle.color(a.judgment) ?? Theme.neutral600, tabularNumbers: true))
                        .accessibilityIdentifier("play-review-judgment")
                }
            }
            if let a, a.judgment == .mistake || a.judgment == .blunder || a.judgment == .inaccuracy,
               let best = uciToSanAt(ply - 1, a.bestUci) {
                Text("Best was \(best)").textStyle(.inline(13, opacity: 0.85))
            }
            if analysis == nil {
                Text(controller.analysisPending ? "Analyzing game…" : "No analysis available.")
                    .textStyle(.inline(12, color: Theme.neutral500, italic: true))
            }
        }
    }

    /// `height:10px; border:1px solid divider; border-radius:5px; overflow:hidden` with the
    /// white share in `#f6e8cd` over `#4a3018`; the width animates like `transition: width .3s`.
    private func evalBar(share: Double) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(Color(hex: 0xF6E8CD))
                    .frame(width: proxy.size.width * CGFloat(share) / 100)
                Rectangle().fill(Color(hex: 0x4A3018))
            }
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.3), value: share)
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.divider, lineWidth: 1))
        .accessibilityLabel("White \(jsRound(share)) percent")
    }

    /// SAN of `uci` in the position after `ply` plies, or nil when it is not a legal move there.
    private func uciToSanAt(_ ply: Int, _ uci: String) -> String? {
        let pos = boot.controller.game.positionAt(ply)
        let legal = pos.generateLegalMoves()
        for m in legal where m.uci == uci {
            return toSAN(pos, m, legalMoves: legal)
        }
        return nil
    }
}
