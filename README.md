# Adaptive Chess

An offline iPhone and iPad chess app, written in Swift and SwiftUI, with an AI opponent that
**models the player and adapts**. It is a 1:1 native port of the earlier TypeScript/Capacitor
app: the same rules engine, search, persona model, adaptation logic, puzzles, progression and
persistence, verified move-for-move and byte-for-byte against fixtures generated from the
original. The "Classical" design system (wood plate, engraved glyph pieces, Cormorant Garamond
and Lora) is reproduced in SwiftUI.

No CocoaPods, no npm, no third-party packages: the app uses Apple frameworks only.

## Requirements

- macOS with **Xcode 27 beta** at `/Applications/Xcode-beta.app` (Swift 6 toolchain).
  Either make it the default with `sudo xcode-select -s /Applications/Xcode-beta.app` or export
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` before every `xcodebuild`,
  `xcrun` and `swift` command below. The examples assume the export.
- An **iPhone 17 Pro** simulator (any iOS 17+ simulator works; the commands name this one).
- No Apple developer account is needed for the simulator (`CODE_SIGNING_ALLOWED=NO`). For a
  device build, open `AdaptiveChess.xcodeproj` in Xcode and pick your team under
  *Signing & Capabilities*. The bundle identifier is `com.adaptivechess.app`.

Deployment target iOS 17.0; the Swift package also builds for macOS 14 so its tests run on the Mac.

## Build, run and test

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
SIM='platform=iOS Simulator,name=iPhone 17 Pro'

# Build the app for the simulator
xcodebuild build -project AdaptiveChess.xcodeproj -scheme AdaptiveChess \
  -destination "$SIM" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Install and launch it
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/AdaptiveChess.app
xcrun simctl launch booted com.adaptivechess.app

# Engine, AI and services tests (Swift Testing, runs on the Mac; release = realistic speed)
( cd Packages/ChessCore && swift test -c release )

# App unit tests + UI tests on the simulator (all three test targets)
xcodebuild test -project AdaptiveChess.xcodeproj -scheme AdaptiveChess \
  -destination "$SIM" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Only one bundle
xcodebuild test ... -only-testing:AdaptiveChessTests
xcodebuild test ... -only-testing:AdaptiveChessUITests
xcodebuild test ... -only-testing:AdaptiveChessUITests/LayoutUITests

# Clean
xcodebuild clean -project AdaptiveChess.xcodeproj -scheme AdaptiveChess -derivedDataPath DerivedData
( cd Packages/ChessCore && swift package clean )
```

Useful variants:

- **iPad**: swap the destination for `name=iPad Pro 13-inch (M5)` or `name=iPad mini (A17 Pro)`.
  `LayoutUITests` checks portrait and landscape on iPad; the landscape case is skipped on
  iPhone because the phone is portrait-only.
- **Screenshots from the UI tests**: `TEST_RUNNER_ADAPTIVE_CHESS_SHOTS=/absolute/dir` makes
  `LayoutUITests` write one PNG per scenario and device (`iPhone-17-Pro-play-start.png` …).
- **Debug launch arguments** (DEBUG builds only, used by the UI tests): `--scenario <name>`
  puts the app straight into a state (`home`, `play-start`, `play-selected`, `play-promotion`,
  `gameover-pvp`, `finished-pvp`, `gameover-ai`, `puzzles`, `insights`, `settings`,
  `home-continue`); `--board-gallery <page>` shows one page of board states (start, selected,
  captures, check, promotion, flipped, design-system sampler) for visual comparison;
  `--reset-state` wipes saved data first. Example:
  `xcrun simctl launch booted com.adaptivechess.app --reset-state --scenario play-promotion`.

## Project layout

```
AdaptiveChess.xcodeproj         app + AdaptiveChessTests + AdaptiveChessUITests targets
AdaptiveChess/                  the iOS app (MainActor default isolation)
  AdaptiveChessApp.swift          @main, scene phases → pause clock / autosave / resume
  Info.plist                      portrait-only iPhone, all orientations on iPad
  DesignSystem/                   Theme (colours, spacing, radii), Typography (bundled fonts,
                                  synthetic oblique), Components (buttons, cards, segmented
                                  controls, section labels, tags)
  Platform/                       AppFeedback (FeedbackService), SoundPlayer (AVAudioEngine
                                  synthesised tones), Haptics (UIKit generators)
  Resources/                      Assets.xcassets (AppIcon, Splash, wood texture, colours),
                                  Fonts (Cormorant Garamond, Lora)
  UI/                             AppBoot, RootView (tab bar + router), DebugScenarios
    Board/                        BoardView, SquareView, PieceGlyph, BoardGestures,
                                  PromotionDialog, BoardGallery
    Screens/                      LoginScreen, HomeScreen, PuzzlesScreen, InsightsScreen,
                                  SettingsScreen, PageLayout
      Game/                       GameScreen, GameScreenModel, SidePanel, ReviewCard,
                                  GameOverDialog, DrawOfferDialog
AdaptiveChessTests/             Swift Testing: launch smoke test, design system, AI speed
AdaptiveChessUITests/           XCTest UI tests: flows, board interaction, layout snapshots
Packages/ChessCore/             local Swift package (Swift 6 language mode)
  Sources/ChessCore/
    Engine/                       Types, Zobrist, MoveList, Position, Game, SAN, PGN, Perft
    AI/                           Eval, Search, Persona, PlayerModel, Adaptation, Openings,
                                  Protocol, AnalyzedMove, DifficultyMode, AIEngine
  Sources/ChessServices/        GameController, AIService, ChessClock, TimeControl, Puzzles,
                                Progression, Store, StoreModels, Storage, Feedback
  Tests/ChessCoreTests/         engine, AI and adaptation tests + JSON fixtures from the TS
  Tests/ChessServicesTests/     clock, store, progression, puzzle validity, controller tests
docs/PORTING_NOTES.md           TS → Swift mapping, phase history, notes, faithfully-ported bugs
```

## Architecture

Four layers. The two package libraries know nothing about SwiftUI, so they run identically in
the app, in `swift test` on the Mac and inside the simulator.

**Engine** (`ChessCore/Engine`) is a deterministic rules engine with zero dependencies.
`Position` holds a 64-square mailbox board with packed 32-bit moves, make/unmake, legal move
generation into a fixed-size `MoveList`, FEN, incremental Zobrist hashing and material logic.
`Game` adds the move history with SAN, every draw rule and `GameResult`. `SAN.swift`,
`PGN.swift` and `Perft.swift` provide notation, PGN import/export and verification counts.

**AI** (`ChessCore/AI`) is the opponent. `evaluate(_:params:)` scores material, piece-square
tables, pawn structure, king safety and mobility with the adaptation knobs in `EvalParams`.
`Search` is iterative-deepening alpha-beta with quiescence, a transposition table, killer and
history heuristics, repetition awareness and a deadline polled every 2048 nodes. `Persona`
turns a 0–20 skill into depth, evaluation noise and a blunder model; `PlayerModel` is the
persistent profile (style features, weaknesses, openings, Elo); `Adaptation` turns the profile
into a plan; `Openings` is the compact named book. `AIEngine` is an **actor**: the search runs
off the main thread and honours Task cancellation, replacing the Web Worker of the TS app.

**Services** (`ChessServices`) is the application layer. `GameController` (`@Observable`,
`@MainActor`) drives one live game: clocks, AI turns, hints, puzzles, constraint games, drills,
draw offers, autosave and the post-game pipeline. `AppState` owns settings, the player model,
progress, the saved game, the archive and recorded mistakes, and persists each through
`Storage`, which writes every value twice (an atomically replaced `<key>.json` in
`Library/Application Support/com.adaptivechess.app/` and `UserDefaults`) so a crash mid-write
still leaves one good copy. `ChessClock` implements Fischer clocks with presets and handicaps;
`Puzzles` and `Progression` hold the engine-verified puzzles, drills, XP, levels, badges and the
daily challenge; `FeedbackService` abstracts sounds and haptics.

**UI** (`AdaptiveChess/`) is SwiftUI with the Observation framework. `AppBoot` runs the
Capacitor migration, loads state, gates on the login screen and resumes the saved game or starts
a new one against the AI. `RootView` hosts the Home, Play, Puzzles, Insights and Settings tabs.
The board (`BoardView` → `SquareView` → `PieceGlyph`) is sized from the viewport width with
62 pt maximum squares, takes tap and drag input through `BoardGestures`, and draws the dot and
ring move targets and the promotion dialog.

### Rules coverage

Castling with all legality conditions, en passant (including the pin edge case),
underpromotion, check and checkmate, stalemate, threefold (claimable) and fivefold (automatic)
repetition, fifty-move (claimable) and seventy-five-move (automatic) rules, insufficient
material, resignation, draw by agreement, flag fall, and the FIDE 6.9 timeout rule (a flag fall
is a draw when the opponent cannot possibly mate). Move generation is verified by perft against
six reference positions.

## Tests

| Target | Framework | Runs on | Contents |
|---|---|---|---|
| `ChessCoreTests` + `ChessServicesTests` (169 tests, 29 suites) | Swift Testing | Mac via `swift test -c release` | perft, rules, draws, SAN/PGN, Zobrist parity, eval, search, persona, player model, adaptation, openings, AI engine, puzzle search, clock, store, progression, puzzle validity, game controller |
| `AdaptiveChessTests` (10 tests) | Swift Testing | simulator | launch scaffold, fonts and board geometry, AI speed budget |
| `AdaptiveChessUITests` (18 tests) | XCTest | simulator | first-launch and navigation flows, board taps and drags, promotion, layout snapshots on iPhone and iPad (landscape skipped on iPhone) |

The package tests assert exact TS parity: the search fixtures pin best move, score, node count,
root scores and PV; the adaptation fixtures pin the plan, notes and rating for three analysed
games. Every function that rolls dice takes an `rng` parameter, so the tests replay the TS tests'
seeded generator and get the same persona picks and mirror decisions.

## How adaptation works

After every finished game against the AI (`GameController.onGameEnd`):

1. **Facts** are extracted from the move record by `extractFacts(_:playerColor:)` (capture
   rate, early-queen ply, castling ply, pawn storms, checks, trade rate, think time) and folded
   into the rolling `StyleFeatures` of the `PlayerModel` by `updateModelAfterGame`.
2. A **background analysis** (`AIEngine.analyze`, 250 ms per move, run as a cancellable Task)
   grades each move as an `AnalyzedMove`. `extractWeaknesses` classifies the player's mistakes
   into `WeaknessKey`s (hanging pieces, missed tactics, back rank, endgame, opening, king
   safety), the centipawn loss feeds the accuracy feature, and moves that lost 200 cp or more
   are stored as `RecordedMistake`s and served back as **personalised puzzles** ("find the move
   you missed"). The grades are attached to the archived game for review.
3. Before the next game, `planForGame(_:mode:aiColor:rng:)` turns the model into an
   `AdaptationPlan` (`EvalParams`, preferred opening tags, notes):
   - *aggressive players* → the AI raises its own king-safety weight and plays solid book lines;
   - *tactical players* → closed-centre preference and closed openings;
   - *defensive players* → space weighting and sharp lines;
   - *positional players* → aggression and mobility, open sharp lines;
   - *materialistic players* → initiative over pawns.
   It also prepares against the player's most frequent opening and, one time in four,
   `pickBookMove` mirrors it back at them.
4. Everything the AI did differently is listed in the plan's notes and shown honestly in the
   **"How I adapted"** section of `GameOverDialog` and on the Insights screen.

## Tuning AI difficulty

Rubber-band Elo, in `Adaptation.swift` and `Persona.swift`:

- The player has a persistent Elo (`updateRating`: K = 48 for the first 10 games, then 24,
  floor 200, history capped at 200 points), updated after each AI game against the AI's
  effective Elo.
- `targetElo(_:mode:)`: **Learn** = player − 90, **Match** = player, **Push me** = player + 90,
  plus a streak band of ±25 Elo per consecutive win or loss capped at ±120, clamped to
  600…2200. Win and the AI firms up; slump and it eases off.
- `eloToSkill` maps that to skill 0–20 (`skillToElo` is 600 + 80 × skill) and
  `personaForSkill(_:moveTimeMs:)` sets: search depth 2/3/4/5/8 for skill ≤2/≤6/≤11/≤16/above,
  Gaussian evaluation noise `(20 − skill)² × 0.55` cp (0 at 20, 220 at 0), a bounded-loss
  candidate window of 30/80/160/320 cp and a blunder rate of 2/6/12/22 %. Mistakes are
  *plausible*: `chooseMove` only picks among moves the search actually scored, never abandons a
  found mate and never exceeds its loss bound. Tune the tables in `personaForSkill` and the
  offsets in `targetElo`.
- The move-time budget is 900 + 300 × depth ms, so a skill-20 reply is bounded by about 3.3 s
  even on a slow device; `AIPerformanceTests` checks it in the simulator.

## Data migration from the Capacitor version

The old app stored its nine `chess.*` keys through `@capacitor/preferences`, which keeps each
value as a JSON string in `UserDefaults.standard` under `CapacitorStorage.<key>`. On first
launch `AppBoot` calls `AppState.migrateFromCapacitor()` before loading state:
`Storage.migrateCapacitorPreferences(from:)` copies each legacy value that has no native
counterpart yet into the new dual-copy storage, never overwrites native data, leaves the legacy
values in place and records `chess.capacitorMigrated` so the import runs once. Settings, player
model, progress, saved game, archive, recorded mistakes, difficulty, player name and guest flag
all carry over, so an upgrade keeps the rating, badges and the game in progress.

## Performance (release, Apple silicon)

| Measurement | Value |
|---|---|
| perft(5) from the start position (4,865,609 nodes) | 0.29 s, about 16.8 M nodes/s |
| search speed (fixture positions) | about 1.33 M nodes/s (the TS ran about 194 k nodes/s in Node) |
| start position, depth 5 | 77,830 nodes in 48 ms |
| transposition table | 262,144 entries, about 6.3 MB |

Debug builds in the simulator search roughly ten to a hundred times slower; the release
configuration is what ships.

## Design fidelity

`Theme.swift` holds the Classical design tokens (colours, spacing, radii), `Typography.swift`
registers the bundled Cormorant Garamond and Lora faces and synthesises the 14° oblique WebKit
produced for italic text, and `Components.swift` reproduces the buttons, cards, segmented
controls and tags. The game screen follows the original markup: wood plate, textured squares,
engraved glyph pieces, dot and ring targets, promotion dialog, side panel and review card.
Layouts were compared against reference screenshots of the TS app at iPhone and iPad viewports.

## Known gaps

The port reproduces the TS app's behaviour, including its bugs; they are listed with their
causes under "Faithfully-ported bugs" in `docs/PORTING_NOTES.md` (for example the unused
Animations setting, the unreachable dead-position result and the closed-centre bonus that only
applies when the AI is White). The launch icon and splash are still the Capacitor placeholders.
