# Porting plan: Adaptive Chess → native Swift + SwiftUI

Branch `swift-native`. The TypeScript app in `src/` is the specification. This document records the
rules of the port, how every TS file becomes Swift, which phase does it, and what each phase must prove
before it is committed.

## RULES

- Goal: a native Swift + SwiftUI app whose features, rules, AI behavior, tuning numbers, UI text and visual design match the TypeScript app. The TS in src/ is the spec. Port logic 1:1: same algorithms, constants, tables, thresholds, strings and save-data shape. Don't redesign or "improve" gameplay.
- Decisions: iOS 17+ (the package also supports macOS 14 so tests run on the Mac). SwiftUI + Observation (@Observable). Swift 6 language mode if it compiles cleanly, otherwise Swift 5 with strict concurrency warnings. Apple frameworks only: no third-party packages, CocoaPods or npm in the final app. Work on branch swift-native, commit once per phase, never commit or push to main.
- Toolchain: prefix every xcodebuild/xcrun/swift command with DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer. Simulator destination 'platform=iOS Simulator,name=iPhone 17 Pro'. Build with CODE_SIGNING_ALLOWED=NO (no Apple Developer account).
- Layout: Packages/ChessCore holds ChessCore (Engine/, AI/) and ChessServices (clock, puzzles, progression, storage, store, controller). The AdaptiveChess app target holds UI/, DesignSystem/, Platform/ (sound, haptics) and Resources/.
- Porting gotchas:
  - Use fixed-width integers for the packed 32-bit moves, and respect JS >>> vs >>.
  - Use Swift's wrapping operators (&+ &* &<<) wherever JS wraps, e.g. mulberry32 and hashing. Zobrist keys are UInt64.
  - Seeded RNGs must be bit-identical: zobrist.ts mulberry32 and the date-seeded daily puzzle.
  - Math.random becomes an injectable RandomNumberGenerator so tests can fix it.
  - Keep Double where TS does float math (eval noise, Elo) and Int where values are integral.
  - Use stable sorts wherever tie order matters (move ordering, root move choice).
  - Codable models must read and write the exact JSON shape that TS JSON.stringify produces: same keys, and missing fields omitted rather than null.
- Parity: when unsure about behavior, run the TS (node/tsx/vitest) to generate expected values and assert them in Swift tests.
- Quality: no stubs, TODOs or placeholders in finished phases. Fix every error and warning you introduce. If the TS has a bug, port it faithfully and log it under "Faithfully-ported bugs". Every phase ends with its check passing, the checklist ticked and a commit "Phase N: …".

## TS baseline (recorded in Phase 0)

`npm install && npm test` on 2026-09-26, vitest 3.2.7, Node 26.9.0, `vitest run` with `testTimeout: 120000`.

| Suite | Tests | Result | Notes |
|---|---|---|---|
| tests/ai.test.ts | 8 | pass | search mates / material, persona choice |
| tests/clock.test.ts | 15 | pass | fake timers |
| tests/controller.test.ts | 38 | pass | aiClient / feedback mocked |
| tests/draws.test.ts | 26 | pass | |
| tests/notation.test.ts | 11 | pass | FEN / SAN / PGN / zobrist |
| tests/perft.test.ts | 6 | pass | 12.8 s, includes perft(5) = 4,865,609 |
| tests/progression.test.ts | 14 | pass | |
| tests/puzzles.test.ts | 16 | pass | 11.0 s, engine-verifies every shipped puzzle |
| tests/rules.test.ts | 21 | pass | |
| tests/store.test.ts | 11 | pass | in-memory localStorage |
| **Total** | **166 tests in 10 files** | **all pass** | 13.2 s wall clock |

Reference screenshots of the TS app (402×874 CSS px, deviceScaleFactor 3, Chromium via Playwright)
are in `.porting/reference/` (gitignored). Each exists as a viewport shot and a `-full` full-page shot:

| File | Shows |
|---|---|
| 01-login | first-launch name prompt |
| 02-home | home after "Continue as guest" |
| 03-play-start | vs-AI game, start position, White to move |
| 04-play-selected | e2 pawn selected, move-target dots on e3/e4 |
| 05-play-promotion | "Promote to" dialog (pass-and-play, auto-queen off) |
| 06-play-gameover-pvp | game-over dialog after Ra8# in pass-and-play |
| 07-play-finished-pvp | finished game with the dialog closed (review controls) |
| 08-play-gameover-ai | game-over dialog after resigning vs the AI ("How I adapted", offers) |
| 09-puzzles | Challenges tab |
| 10-insights | Insights tab after one game |
| 11-settings | Settings tab |
| 12-home-continue | home with a resumable game ("Continue" card) |

Regenerate: `npm run dev -- --port 5180` then `node .porting/tools/capture.mjs http://127.0.0.1:5180`
(the tools folder has its own `package.json` with Playwright; nothing is added to the app's `package.json`).

## Mapping: TypeScript → Swift

Package root: `Packages/ChessCore/Sources/`. App root: `AdaptiveChess/`.

### src/

| TS file | Swift file(s) | Phase |
|---|---|---|
| src/engine/types.ts | ChessCore/Engine/Types.swift (PieceColor, PieceType, Piece as Int8 code, squares, CastlingRights / MoveFlags option sets, Move packing as UInt32, deltas) | 1 |
| src/engine/zobrist.ts | ChessCore/Engine/Zobrist.swift (mulberry32 on UInt32, key tables as UInt64 = hi<<32 \| lo) | 1 |
| src/engine/position.ts | ChessCore/Engine/Position.swift (FEN, attacks, pseudo/legal generation, make/unmake, material, insufficient/dead) + Board.swift (64 inline Int8, no heap) + MoveList.swift (256-slot inline move buffer) | 1 |
| src/engine/perft.ts | ChessCore/Engine/Perft.swift | 1 |
| src/engine/game.ts | ChessCore/Engine/Game.swift (`struct Game`, GameStatus, ResultKind with the TS raw strings, GameResult, HistoryEntry, repetition table, claims, automatic ends, FIDE 6.9 timeout) | 2 |
| src/engine/san.ts | ChessCore/Engine/SAN.swift (toSAN, normalizeSAN, fromSAN with LAN fallback) | 2 |
| src/engine/pgn.ts | ChessCore/Engine/PGN.swift (PGNHeaders ordered like a JS object, toPGN with 80-column wrap, fromPGN stripping comments/NAGs/variations, PGNError) | 2 |
| src/ai/eval.ts | ChessCore/AI/Eval.swift (PIECE_VALUE, PSTs, EvalParams, phase, shield, pawn structure, space, rooks, mobility, aggression, bishop pair, closedPref) | 3 |
| src/ai/search.ts | ChessCore/AI/Search.swift (TT 1<<18, killers/history, iterative deepening with soft stop, root MARGIN 250, quiescence with delta pruning, stable move ordering, PV) | 3 |
| src/ai/persona.ts | ChessCore/AI/Persona.swift (personaForSkill, skill↔Elo, Box–Muller gaussian, chooseMove with injectable RNG) | 3 |
| src/ai/protocol.ts | ChessCore/AI/AnalyzedMove.swift (Judgment, AnalyzedMove — done in phase 2 because the archive persists them); ChessCore/AI/Protocol.swift (MoveRequest/Response, HintRequest/Response, AnalyzeRequest/Response) | 2 / 3 |
| src/ai/worker.ts | ChessCore/AI/AIEngine.swift (handleMove incl. book bypass, handleHint depth 5 / 1500 ms, judge thresholds 50/120/250, handleAnalyze depth 4 with −400 fallback) | 3 |
| src/ai/openings.ts | ChessCore/AI/Openings.swift (BOOK of 22 lines, identifyOpening, bookContinuations) | 4 |
| src/ai/adaptation.ts | ChessCore/AI/DifficultyMode.swift (done in phase 2, persisted by SavedGame); ChessCore/AI/Adaptation.swift (targetElo band ±120, planForGame style switch + notes, mirror-opening 25 %, pickBookMove; RNG injected) | 2 / 4 |
| src/ai/playerModel.ts | ChessCore/AI/PlayerModel.swift (PlayerModel v1 Codable, roll, extractFacts, extractWeaknesses, classifyStyle, updateRating K 48/24, updateModelAfterGame, topWeaknesses; clock injected for `t`) | 4 |
| src/app/aiClient.ts | ChessServices/AIClient.swift (async bridge to AIEngine running off the main actor; requestAiMove / requestHint / requestAnalysis(perMoveMs 350)) | 5 |
| src/app/clock.ts | ChessServices/TimeControl.swift (TimeControl Codable, optional per-side overrides omitted when nil — phase 2); ChessServices/ChessClock.swift (TIME_PRESETS, customTimeControl, ChessClock with injectable now()/ticker at 100 ms, formatClock) | 2 / 5 |
| src/app/storage.ts | ChessServices/Storage.swift (KeyValueStore protocol; UserDefaults implementation keyed exactly `chess.*`; in-memory implementation for tests) | 5 |
| src/app/store.ts | ChessServices/StoreModels.swift (GameMode, ClockRemaining `[w, b]`, SavedGame, ArchivedGame, PlayerColorCode "w"/"b" — phase 2); ChessServices/Store.swift (Settings, RecordedMistake, AppState @Observable, loadAll merge-with-defaults, persist with caps 100/60, recordMistakes) | 2 / 5 |
| src/app/puzzles.ts | ChessServices/Puzzles.swift (PUZZLES 15, DRILLS 4, CONSTRAINTS 3 — verbatim data) | 5 |
| src/app/progression.ts | ChessServices/Progression.swift (Progress, levelForXp, BADGES 14, refreshBadges, UTC dateKey, dailyPuzzle hash, streaks, WEAKNESS_PUZZLES/LABEL, offerChallenges) | 5 |
| src/app/controller.ts | ChessServices/GameController.swift (@Observable; newGame/resume/challengeById, move flow, AI pacing 450 ms + failsafe, puzzles/drills/constraints, draws, hints, onGameEnd XP/badges/rating, post-game analysis, archive, save) | 6 |
| src/app/feedback.ts | AdaptiveChess/Platform/SoundPlayer.swift (AVAudioEngine oscillator tones with the same freq/duration/wave/gain/offset per event), AdaptiveChess/Platform/Haptics.swift (UIImpactFeedbackGenerator light/medium/heavy, UINotificationFeedbackGenerator success/warning), ChessServices/Feedback.swift (Sound/Haptic protocols the controller calls) | 6 |
| src/ui/dom.ts | AdaptiveChess/DesignSystem/Components.swift (LabelStyle 12 px / 0.12 em uppercase, CardStyle, Segmented control, buttons, tags) | 7 |
| src/ui/boardView.ts | AdaptiveChess/UI/Board/BoardView.swift, PieceGlyph.swift (♚♛♜♝♞♟ with engraved shadows), SquareView.swift (wood tiles + overlays, highlights, target dots/rings, coordinates), BoardGestures.swift (tap + drag, ghost piece) | 7 |
| src/ui/router.ts | AdaptiveChess/UI/RootView.swift (route enum, bottom tab bar ⌂ ♞ ✦ ◔ ⚙ with labels, hidden on login) | 8 |
| src/ui/loginScreen.ts | AdaptiveChess/UI/Screens/LoginScreen.swift | 8 |
| src/ui/homeScreen.ts | AdaptiveChess/UI/Screens/HomeScreen.swift (Continue, New game, Daily challenge, Your progress, Import game) | 8 |
| src/ui/gameScreen.ts | AdaptiveChess/UI/Screens/Game/GameScreen.swift, StatusLine.swift, SidePanel.swift (Mode/AI level/Timer/Captured/Moves/actions), ReviewCard.swift (eval bar + judgments), PromotionDialog.swift, GameOverDialog.swift, DrawOfferDialog.swift | 8 |
| src/ui/puzzlesScreen.ts | AdaptiveChess/UI/Screens/PuzzlesScreen.swift | 8 |
| src/ui/statsScreen.ts | AdaptiveChess/UI/Screens/InsightsScreen.swift (rating graph, level, style, weaknesses, openings, badges, recent games) | 8 |
| src/ui/settingsScreen.ts | AdaptiveChess/UI/Screens/SettingsScreen.swift | 8 |
| src/main.ts | AdaptiveChess/AdaptiveChessApp.swift + AdaptiveChess/UI/AppBoot.swift (loadAll, login gating, resume-or-new AI game) | 8 |

### tests/

| TS test file | Swift test file(s) | Phase |
|---|---|---|
| tests/perft.test.ts (6) | Packages/ChessCore/Tests/ChessCoreTests/PerftTests.swift | 1 |
| tests/rules.test.ts (21) | ChessCoreTests/RulesTests.swift — all 21, one `@Test` per `it` with the TS names (phase 1 shipped the Position-only subset) | 2 |
| tests/notation.test.ts (11) | ChessCoreTests/NotationTests.swift — all 11 (phase 1 shipped FEN round-trip and zobrist consistency) | 2 |
| tests/draws.test.ts (26) | ChessCoreTests/DrawsTests.swift | 2 |
| tests/ai.test.ts (8) | ChessCoreTests/SearchTests.swift, ChessCoreTests/PersonaTests.swift | 3 |
| tests/puzzles.test.ts (16) | Packages/ChessCore/Tests/ChessServicesTests/PuzzleValidityTests.swift | 5 |
| tests/clock.test.ts (15) | ChessServicesTests/ClockTests.swift (manual clock + ticker instead of vi fake timers) | 5 |
| tests/progression.test.ts (14) | ChessServicesTests/ProgressionTests.swift | 5 |
| tests/store.test.ts (11) | ChessServicesTests/StoreTests.swift (in-memory KeyValueStore) | 5 |
| tests/controller.test.ts (38) | ChessServicesTests/GameControllerTests.swift (scripted AIClient, no-op feedback, manual clock) | 6 |
| — (no TS tests) | ChessCoreTests/ZobristTests.swift, EnginePortTests.swift (FEN laxness, move packing, copy semantics, Game/PGN details, SAN parity against `Fixtures/san-fixtures.json`), ChessServicesTests/StoreModelsTests.swift (`Fixtures/saved-game.json` round-trip, archived-PGN parity), EvalTests.swift, PlayerModelTests.swift, AdaptationTests.swift, OpeningsTests.swift: parity fixtures generated by running the TS | 1, 2, 3, 4 |

### public/ and app shell

| File | Swift / resource | Phase |
|---|---|---|
| public/styles.css | AdaptiveChess/DesignSystem/Theme.swift (colour tokens, ramps, spacing, radii, shadows), Typography.swift, Components.swift | 7 |
| public/fonts.css, public/assets/fonts/*.woff2 | AdaptiveChess/Resources/Fonts/ (Cormorant Garamond 400/600, Lora 400/600 converted to TTF), `UIAppFonts` in Info.plist | 7 |
| public/assets/wood.jpg | AdaptiveChess/Resources/Assets.xcassets/wood.imageset | 7 |
| index.html, capacitor.config.ts, vite.config.ts, tsconfig.json, package.json | AdaptiveChess.xcodeproj + AdaptiveChess/Info.plist (bundle id com.adaptivechess.app, display name "Chess", #f3f2f2 launch background) | 0, removed in 10 |
| ios/App (Capacitor shell), android/ | AdaptiveChess/ app target (AppIcon and Splash copied in phase 0) | 0, removed in 10 |

## Phases

### Phase 0 — Setup
- [x] Branch `swift-native` checked out; nothing committed to main
- [x] Read README, src/, tests/, public/, index.html, capacitor.config.ts, package.json, ios/App
- [x] `npm install && npm test` baseline recorded above
- [x] Reference screenshots in `.porting/reference/`; `.porting/` gitignored
- [x] PORTING_PLAN.md (rules, mapping, phases, empty bug/notes sections)
- [x] Packages/ChessCore: iOS 17 / macOS 14, targets ChessCore (Engine/, AI/), ChessServices, ChessCoreTests, ChessServicesTests, one placeholder test each, Swift 6 language mode
- [x] AdaptiveChess.xcodeproj (objectVersion 77, file-system-synchronized groups), AdaptiveChess/{UI,DesignSystem,Platform,Resources}, AdaptiveChessTests, AdaptiveChessUITests, local package dependency
- [x] Bundle id com.adaptivechess.app, display name "Chess", iOS 17, iPhone portrait only, iPad all orientations, AppIcon + Splash copied, launch screen on #f3f2f2, placeholder root view "Chess"
- [x] Check: `swift test` passes in Packages/ChessCore; `xcodebuild` builds for the iPhone 17 Pro simulator; app installs, launches and shows the placeholder (screenshot `.porting/phase0-sim.png`)
- [x] Commit "Phase 0: scaffold native project and porting plan"

### Phase 1 — Engine core
- [x] Types.swift: colours, piece codes, `PIECE_CHARS`, square helpers, castle/flag constants, `Move` as UInt32 with the exact bit layout, `moveToUci`, delta tables
- [x] Zobrist.swift: mulberry32 bit-identical to TS (UInt32 wrapping arithmetic, `>>>` as logical shift), tables generated in the same order, `hashKey` string identical to TS (`lo.toString(36) + '.' + hi.toString(36)`)
- [x] Position.swift: FEN load/emit, attack detection, pseudo-legal and legal generation in the same move order (promotions Q,R,B,N), EP square only when capturable, make/unmake with undo stack, incremental hashing, material helpers, insufficient and dead position
- [x] Perft.swift
- [x] Tests: PerftTests (all six positions to the listed depths), ZobristTests (first mulberry32 outputs and selected keys captured from TS), RulesTests (Position cases), NotationTests (FEN round-trip, incremental hash = recompute over 5×120 random plies with the same LCG, unmake restores FEN)
- [x] Check: `swift test` green in Packages/ChessCore with zero warnings
- [x] Commit "Phase 1: engine core"

### Phase 2 — Game rules & notation
- [x] Game.swift: status, result kinds and messages, history entries with optional `clockMs`/`thinkMs`, repetition counting, `play`/`playSAN`/`undo`, resign, FIDE 6.9 timeout, draw offers, claimable and automatic draws (3/5-fold, 50/75 moves, insufficient, dead), `positionAt`, `sanLine`, `uciLine`, `capturedBy`
- [x] SAN.swift and PGN.swift with the same headers ("Adaptive Chess", "Local", "????.??.??", "-"), SetUp/FEN, 80-column wrap, import tolerant of comments, NAGs, variations and `0-0`
- [x] Codable store records with the exact TS JSON shape: `DifficultyMode`, `Judgment`/`AnalyzedMove` (ChessCore/AI), `TimeControl`, `GameMode`, `ClockRemaining`, `SavedGame`, `ArchivedGame` (ChessServices); TS-generated fixture `Tests/ChessServicesTests/Fixtures/saved-game.json` decodes and re-encodes to equivalent JSON
- [x] Tests: RulesTests (all 21), DrawsTests (all 26), NotationTests (all 11) — one Swift test per TS `it`, same names; EnginePortTests (Swift-only checks + SAN parity fixture of 397 moves), StoreModelsTests
- [x] Check: `swift test -c release` green (98 tests, 0.33 s) and `swift test` green (18 s), zero warnings; app `xcodebuild … build` succeeds
- [x] Commit "Phase 2: game rules and notation"

### Phase 3 — AI search & eval
- [ ] Eval.swift: every table and weight verbatim; `Math.round` semantics (round half up toward +∞) preserved
- [ ] Search.swift: TT, killers, history, iterative deepening, deadline/soft-stop, root window with MARGIN 250, alpha-beta with check extension and repetition/insufficient draws, quiescence with delta pruning, MVV-LVA, stable ordering, PV extraction; node counting identical
- [ ] Persona.swift, Protocol.swift, AIEngine.swift (move/hint/analyze/judge)
- [ ] Tests: SearchTests, PersonaTests (same LCG as the TS tests), EvalTests (static evals of fixed FENs captured from TS), fixed-depth search parity (best move, score, node count for chosen positions with an effectively infinite time budget)
- [ ] Check: `swift test` green; the 15 shipped puzzles verify at depth 8 like `tests/puzzles.test.ts` (run here as a smoke test, formalised in phase 5)
- [ ] Commit "Phase 3: AI search and eval"

### Phase 4 — Player model & adaptation
- [ ] PlayerModel.swift: Codable with the exact keys, `lastAdaptation` omitted when absent, `ratingHistory` cap 200, openings cap 12, streak rules, weakness thresholds, style classification
- [ ] Adaptation.swift and Openings.swift with an injectable RNG for the 25 % mirror and book picks
- [ ] Tests: PlayerModelTests, AdaptationTests, OpeningsTests with fixtures generated from the TS; JSON round-trip against a TS-produced `chess.playerModel` blob
- [ ] Check: `swift test` green
- [ ] Commit "Phase 4: player model and adaptation"

### Phase 5 — Services
- [ ] ChessClock.swift (100 ms ticker, low-time once at ≤ 20 s, flag at 0, increment only for the side on move), TimeControl presets and custom clamping, `formatClock`
- [ ] Storage.swift (`chess.*` keys in UserDefaults, corrupt values read as absent), Store.swift (defaults merge, caps), Puzzles.swift, Progression.swift (UTC day key, daily hash, streaks, badges, offers)
- [ ] AIClient.swift: off-main-actor engine calls with the same request shapes and per-move budgets
- [ ] Tests: ClockTests, StoreTests, ProgressionTests, PuzzleValidityTests
- [ ] Check: `swift test` green; a `chess.savedGame` / `chess.progress` / `chess.archive` blob written by the TS app decodes and re-encodes to identical JSON keys
- [ ] Commit "Phase 5: services"

### Phase 6 — Controller & feedback
- [ ] GameController.swift: all fields and methods of `controller.ts`, including think-time budget `900 + maxDepth·300` capped by `max(150, remaining/40)`, 450 ms reply pacing, stale-reply guard via `moveSeq`, failsafe legal move, puzzle validation via hint score < −90 000, draw acceptance rule, XP 40/20/10, giant-slayer, constraint checks, post-game analysis and mistake recording, archive naming `You` / `AI (elo)`
- [ ] Feedback protocols in ChessServices; SoundPlayer.swift and Haptics.swift in the app's Platform/
- [ ] Tests: GameControllerTests (38 cases) with scripted AI replies and a manual clock
- [ ] Check: `swift test` green
- [ ] Commit "Phase 6: controller and feedback"

### Phase 7 — Design system & board
- [ ] Theme.swift: every token in `public/styles.css` (bg, surface, text, accent, accent-2, divider, neutral/accent ramps, fonts, spacing, radii, shadows)
- [ ] Fonts: Cormorant Garamond 400/600 and Lora 400/600 bundled and registered; Typography.swift maps h1–h6 and body sizes
- [ ] Components.swift: buttons (primary/secondary/ghost/icon/block), card, kicker/title/body/meta, tags, segmented control, input, dialog backdrop/dialog, table, hr
- [ ] BoardView: `--sq = min(62, (width − 60)/8)`, wood plate with 700 px tile and sepia filter, light/dark overlays, engraved glyph pieces, selected/hint/check/last-move highlights, target dots and capture rings, coordinates, flip, tap-and-drag with ghost piece
- [ ] Check: app builds; a preview/simulator screenshot of the board matches `03-play-start` and `04-play-selected`
- [ ] Commit "Phase 7: design system and board"

### Phase 8 — Screens
- [ ] RootView tab shell (Home ⌂, Play ♞, Puzzles ✦, Insights ◔, Settings ⚙; hidden on login; safe areas)
- [ ] LoginScreen, HomeScreen, GameScreen (+ status line, side panel cards, review card, promotion / game-over / draw-offer dialogs, PGN export via share sheet), PuzzlesScreen, InsightsScreen (SVG polyline → `Path`), SettingsScreen — all strings verbatim
- [ ] AppBoot: loadAll, login gating, resume saved game or start vs-AI as White
- [ ] Check: app builds and runs on the iPhone 17 Pro simulator; simulator screenshots of every screen saved next to the references in `.porting/` and compared
- [ ] Commit "Phase 8: screens"

### Phase 9 — QA
- [ ] `swift test` (package) and `xcodebuild test` (AdaptiveChessTests + AdaptiveChessUITests) green; UI tests cover login → guest → play a move → promotion → game over, puzzles, settings toggles
- [ ] Side-by-side screenshot review against `.porting/reference/`; fix visual drift
- [ ] Save-data compatibility: JSON produced by the TS app loads; JSON produced by the Swift app has identical keys and types
- [ ] Performance: perft(5) and AI reply latency at skill 20 acceptable on the simulator; no main-thread stalls while the AI thinks
- [ ] Zero compiler warnings across package and app; Swift 6 language mode confirmed
- [ ] Commit "Phase 9: QA"

### Phase 10 — Cleanup & PR
- [ ] Remove the Capacitor/TS app: src/, tests/, public/, index.html, capacitor.config.ts, vite.config.ts, tsconfig.json, package.json, package-lock.json, ios/App, android/
- [ ] Update README.md for the native project (build, test, layout); update .gitignore
- [ ] Final `swift test` + `xcodebuild build` from a clean clone of the branch
- [ ] Commit "Phase 10: cleanup" and open a pull request from `swift-native` into `main` on tarun6k/ios-chess (do not push to main)

## Faithfully-ported bugs

- **En-passant square from FEN is always hashed (position.ts `loadFen` vs `makeMove`).** `makeMove` records `ep` only when an enemy pawn can actually capture (FIDE position identity), but `loadFen` takes the FEN's ep square verbatim and `computeHash` XORs it in. So `…/PPPP1PPP/RNBQKBNR b KQkq e3 0 1` loaded from FEN hashes to `qsljuo.x3ajeo`, while the identical position reached by playing 1.e4 hashes to `9741ik.tbz9di`. Only affects repetition counting in games started from such a FEN. Ported as-is; both values are asserted in `ZobristTests`.
- **`loadFen` does not reset the king squares.** `kingSq` keeps its previous value (`[4, 60]` initially) for a side whose king is missing from the FEN. Position is only ever loaded with two kings by the app, so it is harmless; ported as-is.
- **`normalizeSAN`'s second replace is a no-op (san.ts).** `.replace(/^([RNBQK])([a-h1-8]?)x/, '$1$2x')` rewrites the match to itself, so the function only strips a trailing run of `+#!?` and trims. Swift does exactly that and documents the dead step in a comment.
- **The `dead-position` result kind is unreachable (game.ts `checkAutomaticEnd`).** `isDeadPosition` is a pure material test (neither side has mating potential) and every material set that satisfies it also satisfies `isInsufficientMaterial`, which is tested first. Such games therefore always end as `insufficient` with "Draw — insufficient material"; the `dead-position` kind and its message "Draw — dead position" exist but never fire. Ported as-is; `EnginePortTests` pins the overlap.
- **A PGN tag line with trailing text is not a header (pgn.ts `fromPGN`).** The header regex demands end-of-line right after `]`, so `[White "A"] ; comment` is left in the move text and the import throws `Illegal or unparseable PGN move: [White`. Ported as-is (asserted in `EnginePortTests`).

## Notes / open questions

- **Fonts (Phase 7):** `public/assets/fonts` ships only `.woff2`; CoreText cannot register WOFF2. Cormorant Garamond 400/600 and Lora 400/600 must be bundled as TTF/OTF. Decide the source: decompress the shipped woff2 with a build-time tool, or take the upstream TTFs of the same versions.
- **Saved data location (Phase 5):** the Capacitor app persists through `@capacitor/preferences`, which stores in `UserDefaults` under keys prefixed `CapacitorStorage.` (e.g. `CapacitorStorage.chess.settings`). Decide whether the native app reads those legacy keys once and migrates them to plain `chess.*`, so existing installs keep their progress.
- **Concurrency:** the TS runs the AI in a Web Worker. Swift 6 language mode compiles cleanly in both the package and the app. The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; package targets stay nonisolated so the search can run off the main actor in a `Task`/actor. The 450 ms reply pacing and the `moveSeq` stale-reply guard carry over unchanged.
- **Timestamps:** TS stores `Date.now()` milliseconds as integers (`ratingHistory[].t`, mistakes `at`, saved-game `savedAt`). Swift uses `Int(Date().timeIntervalSince1970 * 1000)`. `dateKey` in progression is the UTC calendar day.
- **Test automation:** the TS app exposes `window.__chess` for scripting. The native app will expose accessibility identifiers instead (names decided in Phase 8), used by `AdaptiveChessUITests`.
- **Toolchain notes:** two simulators named "iPhone 17 Pro" exist on this Mac (`EFDAE60C…` is the booted one, `8A385C66…` is shut down); the name-based destination builds fine, and `simctl` commands use `booted`. `xcodebuild` prints an `appintentsmetadataprocessor` notice on every build; it is a tool message, not a compiler warning. Port 5173 was taken by an unrelated process, so the reference captures were made with Vite on port 5180.
- **Phase 1 engine performance (release, `swift test -c release --no-parallel`, Apple Silicon Mac, Swift 6.4):** perft(5) from the start position = 4,865,609 nodes in **0.29 s (~16.8 Mnps)**; kiwipete perft(4) 0.24 s, position 5 perft(4) 0.12 s, position 6 perft(4) 0.20 s. The whole ChessCore suite (32 tests) runs in 0.4 s in release. In debug (`swift test`) the same perft(5) takes ~19 s (the inline-tuple `Board`/`MoveList` accessors are not inlined at -Onone), so the debug suite takes ~20 s; that is the trade-off for a heap-free hot path. Measured with the parallel runner the release perft(5) reads ~0.37 s because the six perft cases share the cores.
- **Phase 1 API notes:** the TS packed move has no piece or capture fields (only from, to, flags, promotion); Swift keeps that exact 19-bit layout. Swift names: `Color`→`PieceColor` (avoids SwiftUI.Color), `typeOf/colorOf/makePiece`→`Piece.type/.color/Piece(type:color:)`, `sqName`→`squareName`, `attacked`→`isAttacked(_:by:)`, `generatePseudo/generateLegal`→`generatePseudoLegalMoves(into:)/generateLegalMoves()`, `toFen`→`fen`, `computeHash`→`recomputeHash()`, `ep`→`enPassant`, `kingSq[c]`→`kingSquare(c)`, `hashLo/hashHi` are views of one `UInt64 hash` (`hi << 32 | lo`). `parseSquare` returns `nil` for malformed names (TS returns an off-board number); `loadFen` throws `FENError` with the TS message text, and additionally rejects a FEN whose piece placement overflows the board (the TS silently drops out-of-range writes into the `Int8Array`). `Piece.empty.color` is `.black` exactly like TS `colorOf(0)`. `mulberry32` is internal to the module (`Mulberry32`), reachable from tests via `@testable`.
- **Phase 2 API notes:** `class Game` became `public struct Game` (a copy is an independent game; `position`, `history`, `result`, `drawOffer` are `private(set)`); `pos`→`position`, `startFen`→`startFEN`, `inCheck()`→`isInCheck()`, `play(move, meta)`→`play(_:clockMs:thinkMs:)`, `playSAN(san, meta)`→`playSAN(_:clockMs:thinkMs:)`, `new Game(fen)` throws `FENError`. `ResultKind` raw values are the TS strings (`timeoutDraw = "timeout-draw"`, `fiftyMove`, `seventyFiveMove`, `deadPosition`); `HistoryEntry.captured` is a `Piece` (`.empty` for TS `0`). `toSAN(pos, move, legalMoves:)`, `normalizeSAN`, `fromSAN` keep their names; `fromSAN` parses the LAN fallback by hand (regex `^([a-h][1-8])[-x]?([a-h][1-8])(?:=?([QRBNqrbn]))?$`). `PgnHeaders` (a JS object) is `PGNHeaders`: insertion-ordered pairs, assignment keeps a key's position, `entries` puts array-index-like keys first in numeric order like `Object.entries`; `toPGN(_:headers:)` merges the defaults then the caller's headers exactly like the TS spread, so a caller-supplied `Result` wins over the game's score. `fromPGN` uses Swift `Regex` literals (JS `\w` → `[A-Za-z0-9_]`, `m` flag → `.anchorsMatchLineEndings()`), JS `\s` / `trim()` are emulated by `isJavaScriptWhitespace`, and it throws `PGNError.illegalMove(token)` (description = the TS message) or `FENError` for a bad FEN header. JS string length for the 80-column wrap is measured in UTF-16 code units.
- **Phase 2 persistence models:** `SavedGame`/`ArchivedGame` live in `ChessServices/StoreModels.swift` with hand-written `Codable` so that `timeControl`, `clockRemaining`, `challengeId`, `aiElo` and `analysis` encode as explicit `null` (TS `| null`), while `TimeControl.whiteBaseMs/blackBaseMs` are omitted when nil (TS optional properties). `playerColor` is a `PieceColor` in Swift and `"w"`/`"b"` in JSON via `PlayerColorCode`; `clockRemaining` is `ClockRemaining {white, black}` encoded as the TS `[w, b]` array; `aiSkill` is `Double` (fractional via `eloToSkill`), every other number is `Int` (ms timestamps, cp evals). `DifficultyMode` and `Judgment`/`AnalyzedMove` were pulled forward into `ChessCore/AI/` because the records persist them; `TimeControl` into `ChessServices/TimeControl.swift`. Key order in emitted JSON is not significant (JSON.parse ignores it); tests compare canonical sorted-key JSON. The fixtures are produced by `.porting/tools/savedgame-dump.ts` (`node_modules/.bin/vite-node .porting/tools/savedgame-dump.ts`), which builds the records the way `controller.ts` `save()`/`archiveGame()` do — three saved games (vs AI with Blitz clock, pass-and-play with all nulls, a puzzle with a handicap clock and challenge id) and three archive entries (Scholar's mate with a real depth-4 analysis replayed from `worker.ts handleAnalyze`, a resigned pass-and-play game, a drill from a Black-to-move FEN with `SetUp`/`FEN` headers) — plus `Tests/ChessCoreTests/Fixtures/san-fixtures.json` (SAN of every legal move in 17 positions, 397 moves; Swift must also generate them in the same order). The archive PGNs are asserted equal to the Swift `toPGN` output character for character. The fixture's `analysis` values came from the TS search at depth 4 with an effectively unlimited time budget, so Phase 3 can reuse them as search-parity expectations.
- **Launch assets:** `AppIcon` and `Splash` copied from `ios/App` are the Capacitor defaults (blue placeholder icon, white splash). The launch screen uses the `LaunchBackground` colour (#f3f2f2) rather than the splash image; replacing the icon artwork is out of scope for the port.
