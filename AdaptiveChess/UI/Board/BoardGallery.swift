// DEBUG-only board gallery: the states the reference screenshots show (start, piece selected,
// capture targets, check, promotion dialog, flipped) plus a design-system sampler, wrapped in
// the gameScreen.ts page layout (header, board, bottom nav) so simulator screenshots line up
// with `.porting/reference/03-play-start.png` etc. Launch with `--board-gallery <page>`.

#if DEBUG
import ChessCore
import SwiftUI

@Observable
final class GalleryPage: Identifiable {
    struct Promotion {
        let color: PieceColor
        let moves: [Move]
    }

    let id: Int
    let title: String
    var state: BoardState
    var promotion: Promotion?

    init(id: Int, title: String, state: BoardState, promotion: Promotion? = nil) {
        self.id = id
        self.title = title
        self.state = state
        self.promotion = promotion
    }

    var status: String {
        let check = state.position.isInCheck() ? "Check · " : ""
        return check + (state.position.turn == .white ? "White" : "Black") + " to move"
    }

    // gameScreen.ts `tapSquare` / `tryMove` / `finishMove`, without the constraint filter.

    func tap(_ sq: Int) {
        if state.targets.contains(where: { $0.to == sq }) {
            commit(state.targets.filter { $0.to == sq })
            return
        }
        let piece = state.position.board[sq]
        if !piece.isEmpty, piece.color == state.position.turn, state.selected != sq {
            state.selected = sq
            state.targets = state.position.legalMoves(from: sq)
        } else {
            clearSelection()
        }
    }

    func drop(from: Int, to: Int) {
        let candidates = state.position.legalMoves(from: from).filter { $0.to == to }
        if candidates.isEmpty {
            clearSelection()
        } else {
            commit(candidates)
        }
    }

    func finish(_ move: Move) {
        let piece = state.position.board[move.from]
        state.position.makeMove(move)
        state.lastMove = (move.from, move.to)
        state.checkSquare = state.position.isInCheck() ? state.position.kingSquare(state.position.turn) : nil
        promotion = nil
        state.interactive = true
        clearSelection()
        BoardView.announce("\(PieceGlyphs.name(piece.type).capitalized) \(squareName(move.to))")
    }

    private func commit(_ candidates: [Move]) {
        if candidates.count > 1 {
            promotion = Promotion(color: state.position.turn, moves: candidates)
            state.interactive = false
        } else if let move = candidates.first {
            finish(move)
        }
    }

    private func clearSelection() {
        state.selected = nil
        state.targets = []
    }
}

struct BoardGallery: View {
    static let launchArgument = "--board-gallery"

    /// `--board-gallery <page>` in the launch arguments, or `nil` when the app was launched normally.
    static var launchPage: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: launchArgument) else { return nil }
        let next = args.index(after: i)
        return next < args.endIndex ? Int(args[next]) ?? 0 : 0
    }

    static func makePages() -> [GalleryPage] {
        func position(_ fen: String) -> Position {
            do { return try Position(fen: fen) } catch { fatalError("gallery FEN \(fen): \(error)") }
        }
        let start = Position()
        let e2 = parseSquare("e2")!

        // 1.e4 d5: the e4 pawn can push to e5 (dot) or take on d5 (ring); d7–d5 was the last move.
        let afterD5 = position("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2")
        let e4 = parseSquare("e4")!

        // 1.f3 e5 2.h3 Qh4+: white is in check; the hint suggests g2–g3.
        let inCheck = position("rnb1kbnr/pppp1ppp/8/4p3/7q/5P1P/PPPPP1P1/RNBQKBNR w KQkq - 1 3")

        // White pawn on g7 ready to promote, black king on e8 (as in 05-play-promotion).
        let promo = position("4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
        let g7 = parseSquare("g7")!
        let promotions = promo.legalMoves(from: g7).filter { $0.to == parseSquare("g8")! }

        return [
            GalleryPage(id: 0, title: "start", state: BoardState(position: start)),
            GalleryPage(id: 1, title: "selected", state: BoardState(position: start, selected: e2, targets: start.legalMoves(from: e2))),
            GalleryPage(id: 2, title: "captures", state: BoardState(
                position: afterD5, selected: e4, targets: afterD5.legalMoves(from: e4),
                lastMove: (parseSquare("d7")!, parseSquare("d5")!)
            )),
            GalleryPage(id: 3, title: "check", state: BoardState(
                position: inCheck,
                lastMove: (parseSquare("d8")!, parseSquare("h4")!),
                checkSquare: inCheck.kingSquare(.white),
                hintMove: Move(from: parseSquare("g2")!, to: parseSquare("g3")!)
            )),
            GalleryPage(id: 4, title: "promotion", state: BoardState(
                position: promo, selected: g7, targets: promotions, interactive: false
            ), promotion: .init(color: .white, moves: promotions)),
            GalleryPage(id: 5, title: "flipped", state: BoardState(position: start, flipped: true)),
            GalleryPage(id: 6, title: "design system", state: BoardState(position: start)),
        ]
    }

    @State private var pages = BoardGallery.makePages()
    @State private var page: Int

    init(initialPage: Int = 0) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(pages) { p in
                Group {
                    if p.id == 6 {
                        DesignSystemSampler()
                    } else {
                        GalleryBoardPage(page: p)
                    }
                }
                .tag(p.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavBar {
                BottomNavItem(icon: "⌂", label: "Home", active: false) {}
                BottomNavItem(icon: "♞", label: "Play", active: true) {}
                BottomNavItem(icon: "✦", label: "Puzzles", active: false) {}
                BottomNavItem(icon: "◔", label: "Insights", active: false) {}
                BottomNavItem(icon: "⚙", label: "Settings", active: false) {}
            }
        }
        .overlay {
            // gameScreen.ts appends the promotion dialog to the screen root, over the nav bar.
            if let current = pages.first(where: { $0.id == page }), let promotion = current.promotion {
                PromotionDialog(color: promotion.color, moves: promotion.moves) { current.finish($0) }
            }
        }
    }
}

/// The gameScreen.ts page: `padding: clamp(20px,4vw,36px) 12px 96px`, the header, then the board
/// row with `margin-top: clamp(16px,3vw,28px)`.
private struct GalleryBoardPage: View {
    @Bindable var page: GalleryPage

    var body: some View {
        GeometryReader { proxy in
            let vw = proxy.size.width
            ScrollView {
                VStack(spacing: 0) {
                    header
                    BoardView(
                        state: page.state,
                        viewportWidth: vw,
                        onSquareTap: { page.tap($0) },
                        onDrop: { page.drop(from: $0, to: $1) }
                    )
                    .padding(.top, min(max(16, 0.03 * vw), 28))
                    .accessibilityIdentifier("board-\(page.title)")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, min(max(20, 0.04 * vw), 36))
                .padding(.horizontal, 12)
                .padding(.bottom, 96)
            }
        }
    }

    /// gameScreen.ts `header`
    private var header: some View {
        VStack(spacing: 0) {
            Text("Chess").textStyle(.gameTitle)
            Rectangle().fill(Theme.divider).frame(width: 64, height: 1).padding(.vertical, 10)
            Text(page.status).textStyle(.gameStatus)
        }
        .multilineTextAlignment(.center)
    }
}

/// Every component in Components.swift once, to eyeball fonts, spacing and colours.
private struct DesignSystemSampler: View {
    @State private var segment = "match"
    @State private var text = ""
    @State private var showDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text("Heading 1").textStyle(.h1)
                Text("Heading 2").textStyle(.h2)
                Text("Heading 3").textStyle(.h3)
                Text("Heading 4").textStyle(.h4)
                Text("Heading 5").textStyle(.h5)
                Text("Heading 6").textStyle(.h6)
                Text("Body text in Lora at 15px with a line-height of 1.55 — the quick brown fox jumps over the lazy dog.").textStyle(.body)
                HStack(spacing: Theme.Space.s2) {
                    Button("Primary") {}.buttonStyle(.primary)
                    Button("Secondary") {}.buttonStyle(.secondary)
                    Button("Ghost") {}.buttonStyle(.ghost)
                    Button("Disabled") {}.buttonStyle(.primary).disabled(true)
                }
                Button("Block primary") { showDialog = true }.buttonStyle(.block(.primary))
                SegmentedControl(
                    options: [.init("learn", "Learn"), .init("match", "Match"), .init("push", "Push me")],
                    selection: $segment
                )
                HStack(spacing: Theme.Space.s2) {
                    Tag("Accent", .accent)
                    Tag("Accent 2", .accent2)
                    Tag("Neutral", .neutral)
                    Tag("Outline", .outline)
                }
                ClassicTextField("Your name", text: $text)
                Card {
                    CardKicker("Kicker")
                    CardTitle("Card title")
                    Text("Card body copy.").textStyle(.body)
                }
                Card(style: .inline) {
                    SectionLabel("Mode")
                    Text("dom.ts CARD_STYLE").textStyle(.body)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        TableCell("Opening", header: true)
                        TableCell("Games", header: true, alignment: .trailing)
                    }
                    HStack(spacing: 0) {
                        TableCell("Italian Game")
                        TableCell("12", alignment: .trailing)
                    }
                }
            }
            .padding(Theme.Space.s4)
        }
        .overlay {
            if showDialog {
                DialogBackdrop {
                    Dialog {
                        DialogTitle("Dialog title")
                        DialogBody("Dialog body text at 14px and 85% opacity.")
                        DialogActions {
                            Button("Cancel") { showDialog = false }.buttonStyle(.secondary)
                            Button("Confirm") { showDialog = false }.buttonStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}
#endif
