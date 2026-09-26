# Adaptive Chess

An offline iOS (and Android) chess app with an AI opponent that **models the player
and adapts** — built on the "Classical" design system from the companion Claude Design
project (`Chess Game.dc.html` is implemented 1:1 as the game screen; the other screens
extend its visual language minimally).

## Quick start

```bash
npm install
npm run dev            # web dev server (http://localhost:5173)
npm test               # full test suite (engine, AI, app layer; includes perft(5) = 4,865,609)
npm run ios            # build web → sync into ios/ → open the Xcode workspace
```

### iOS

Requirements on this machine:

- Xcode 27 beta at `/Applications/Xcode-beta.app`. Either make it the default
  (`sudo xcode-select -s /Applications/Xcode-beta.app`) or export
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` before any
  `npx cap` / `xcodebuild` / `xcrun` command.
- CocoaPods. `npx cap sync ios` runs `pod install` in `ios/App` for you.

Build and run on the simulator from the command line:

```bash
npm run build && npx cap sync ios
cd ios/App
xcodebuild -workspace App.xcworkspace -scheme App -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch booted com.adaptivechess.app
```

For a device build, open the workspace (`npx cap open ios`) and set your team under
*Signing & Capabilities*. The bundle identifier is `com.adaptivechess.app`.

What is tracked in `ios/` versus generated: the Xcode project, `Info.plist`,
`AppDelegate.swift`, the asset catalog and `Podfile` are committed. `Pods/`,
`DerivedData/`, the synced web bundle in `App/App/public/`, and the generated
`capacitor.config.json` / `config.xml` are ignored and recreated by `npx cap sync ios`.

iOS-specific behaviour worth knowing:

- **Safe areas** — `index.html` sets `viewport-fit=cover`; `public/styles.css` pads
  `#app` and the bottom nav with `env(safe-area-inset-*)`. `capacitor.config.ts` sets
  `contentInset: 'never'` and a webview `backgroundColor` matching `--color-bg` so
  nothing flashes white behind the app.
- **Orientation** — iPhone is portrait-only (`UISupportedInterfaceOrientations`). The
  board is sized from viewport width with 62px-max squares, which does not fit a
  landscape phone. iPad keeps all orientations; its height is sufficient.
- **First launch** — `src/ui/loginScreen.ts` asks for a name or a guest opt-out once;
  the choice is persisted via Capacitor Preferences and the screen never returns.
  `src/ui/router.ts` re-asserts scroll position after the iOS keyboard dismisses.

### Android

```bash
npm run android        # build web → sync → assemble debug APK
```

The debug APK lands in `android/app/build/outputs/apk/debug/app-debug.apk`.
Building needs a JDK 21 (`JAVA_HOME=/opt/homebrew/opt/openjdk@21`) and the Android SDK
(`ANDROID_HOME=~/Library/Android/sdk`, platform 35).

## Architecture

Three strictly separated layers — the rules engine and AI know nothing about the DOM,
so they run identically in the UI thread, the Web Worker, and Vitest:

```
src/engine/    deterministic rules engine (zero dependencies)
  types.ts       board/move encodings (packed 32-bit moves)
  position.ts    make/unmake, legal movegen, FEN, Zobrist hashing, material logic
  game.ts        game lifecycle: SAN history, every draw rule, results
  san.ts, pgn.ts notation + PGN import/export
  perft.ts       verification node counts

src/ai/        the opponent
  eval.ts        material + PSTs + pawn structure + king safety + mobility,
                 with adaptation knobs (EvalParams)
  search.ts      iterative-deepening alpha-beta, quiescence, transposition
                 table, killers/history, repetition-aware
  persona.ts     skill → depth/noise/blunder model (human-like errors)
  playerModel.ts persistent player model: style features, weaknesses, openings, Elo
  adaptation.ts  player model → eval params, opening prep, difficulty band
  openings.ts    compact named opening book
  protocol.ts    request/response types shared with the worker
  worker.ts      Web Worker entry — search never blocks the UI

src/app/       application services
  controller.ts  one live game: clocks, AI turns, challenges, autosave
  aiClient.ts    promise-based bridge to the worker
  clock.ts       Fischer clocks, presets, handicaps, flag/low-time events
  puzzles.ts     engine-verified puzzles, endgame drills, constraint games
  progression.ts XP, levels, badges, daily challenge + streaks
  store.ts       app state + crash-safe persistence
  storage.ts     Preferences (native) + localStorage (web), written to both
  feedback.ts    synthesized sounds + haptics

src/ui/        screens (vanilla TS, design-system CSS from public/styles.css)
  router.ts, dom.ts, boardView.ts
  loginScreen, homeScreen, gameScreen, puzzlesScreen, statsScreen, settingsScreen
```

**Rules coverage**: castling with all legality conditions, en passant (incl. the
pin edge case), underpromotion, stalemate, threefold (claim) / fivefold (auto),
fifty (claim) / seventy-five (auto) move rules, insufficient material, dead
position, resignation, draw offers, and the FIDE 6.9 timeout rule (flag fall is
a draw when the opponent cannot possibly mate).

## Tests

```
tests/perft.test.ts        move generation vs six reference positions
tests/rules.test.ts        castling, en passant, promotion, check/mate edge cases
tests/draws.test.ts        every draw rule
tests/notation.test.ts     SAN / PGN round trips
tests/ai.test.ts           search finds mates, persona error model
tests/puzzles.test.ts      every shipped puzzle verified by the engine
tests/clock.test.ts        Fischer clock, increments, low-time, flag fall, formatting
tests/progression.test.ts  levels, badges, daily streaks, AI-offered challenges
tests/store.test.ts        persistence round trips, migrations, caps
tests/controller.test.ts   game flow with a mocked AI worker: turns, puzzles,
                           constraints, drills, clocks, resume, hints, analysis
```

`npm test` runs everything; `npm run test:perft` runs only the perft suite.

## How adaptation works

After every finished AI game:

1. **Facts** are extracted from the move record (capture rate, early-queen ply,
   castling ply, pawn storms, checks, trade rate, think time) and folded into
   rolling style features (`playerModel.ts`).
2. A **background analysis** pass (same engine, in the worker) grades each of the
   player's moves; mistakes are classified into weaknesses — hanging pieces,
   missed tactics, back-rank, endgame, opening, king safety — and big mistakes
   are saved verbatim as **personalized puzzles** ("find the move you missed").
3. Before the next game, `planForGame()` turns the model into behavior:
   - *aggressive players* → the AI weights its own king safety up and plays solid book lines;
   - *tactical players* → closed-center preference (locked-pawn eval bonus), closed openings;
   - *passive players* → space-grab weighting and sharp lines;
   - *materialistic players* → initiative over pawns.
   It also prepares against the player's most-frequent opening — and ~25% of the
   time mirrors it back at them.
4. Everything the AI did differently is shown honestly in the post-game
   **"How I adapted"** panel and on the Insights screen.

## Tuning AI difficulty

Rubber-band Elo, in `adaptation.ts` / `persona.ts`:

- The player has a persistent Elo (K=48 first 10 games, then 24), updated after
  each AI game against the AI's effective Elo.
- Mode offsets: **Learn** = player−90, **Match** = player, **Push me** = player+90,
  plus a streak band of ±25 Elo per consecutive win/loss (capped ±120) — win and
  the AI firms up, slump and it eases off.
- Target Elo maps to skill 0–20 (`eloToSkill`), which sets: search depth (2–8),
  Gaussian evaluation noise (0–220 cp), a bounded-loss candidate window, and the
  blunder rate. Mistakes are *plausible*: the persona only picks among moves the
  search actually scored, never abandons a found mate, and never hangs a piece
  outside its loss bound. Tune the depth/noise tables in `personaForSkill()` and
  the offsets in `targetElo()`.

## Design fidelity

`public/styles.css` is the Classical design system verbatim (fonts bundled
locally for offline); the game screen reproduces the design file's exact markup
and inline styles — wood plate, textured squares, engraved glyph pieces, dot/ring
targets, segmented controls, promotion dialog. Extensions (difficulty picker,
draw/resign/hint, game-over sheet, review mode, Home/Puzzles/Insights/Settings)
reuse only tokens and components from that system.
