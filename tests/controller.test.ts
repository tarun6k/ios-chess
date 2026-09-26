import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// The controller talks to a Web Worker, WebAudio and native haptics — none of
// which exist under Vitest. Replace them with scriptable stand-ins.
vi.mock('../src/app/aiClient', () => ({
  requestAiMove: vi.fn(),
  requestHint: vi.fn(),
  requestAnalysis: vi.fn(),
}));
vi.mock('../src/app/feedback', () => {
  const noop = (): void => {};
  const asyncNoop = async (): Promise<void> => {};
  return {
    sound: {
      move: noop, capture: noop, check: noop, castle: noop, promote: noop,
      gameWin: noop, gameLoss: noop, gameDraw: noop, lowTime: noop, error: noop,
    },
    haptic: { light: noop, medium: noop, heavy: noop, success: asyncNoop, warning: asyncNoop },
  };
});
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => false } }));
vi.mock('@capacitor/preferences', () => ({ Preferences: {} }));

import { GameController } from '../src/app/controller';
import { requestAiMove, requestHint, requestAnalysis } from '../src/app/aiClient';
import { state, DEFAULT_SETTINGS, SavedGame, RecordedMistake } from '../src/app/store';
import { newProgress } from '../src/app/progression';
import { newPlayerModel } from '../src/ai/playerModel';
import { PUZZLES, CONSTRAINTS, Drill } from '../src/app/puzzles';
import { TIME_PRESETS } from '../src/app/clock';
import { START_FEN } from '../src/engine/position';
import { WHITE, BLACK, moveToUci } from '../src/engine/types';
import { MoveResponse, HintResponse, AnalyzeResponse, AnalyzedMove } from '../src/ai/protocol';

function pending<T>(): Promise<T> { return new Promise<T>(() => {}); }

const moveRes = (uci: string): MoveResponse =>
  ({ id: 0, type: 'move', uci, score: 0, depth: 1, nodes: 1, choiceIndex: 0, bestUci: uci });
const hintRes = (uci: string, score: number): HintResponse => ({ id: 0, type: 'hint', uci, score });
const analysed = (uci: string, bestUci: string, cpLoss: number): AnalyzedMove => ({
  uci, bestUci, cpLoss, evalBefore: 0, evalAfter: -cpLoss,
  judgment: cpLoss >= 200 ? 'blunder' : cpLoss > 0 ? 'inaccuracy' : 'best',
});

/** Script the AI's replies in order; once exhausted it stays silent forever. */
function scriptAi(...ucis: string[]): void {
  const queue = [...ucis];
  vi.mocked(requestAiMove).mockImplementation(() =>
    queue.length ? Promise.resolve(moveRes(queue.shift()!)) : pending<MoveResponse>());
}

function play(c: GameController, uci: string): void {
  const m = c.uciToMove(uci);
  if (m === null) throw new Error(`illegal in test: ${uci}`);
  expect(c.playMove(m)).toBe(true);
}

/** Let the AI's humanlike 450ms pause elapse and promises settle. */
const settle = async (): Promise<void> => { await vi.advanceTimersByTimeAsync(500); };

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-06-01T09:00:00Z'));
  vi.mocked(requestAiMove).mockReset().mockImplementation(() => pending<MoveResponse>());
  vi.mocked(requestHint).mockReset().mockImplementation(() => pending<HintResponse>());
  vi.mocked(requestAnalysis).mockReset().mockImplementation(() => pending<AnalyzeResponse>());
  state.settings = { ...DEFAULT_SETTINGS };
  state.model = newPlayerModel();
  state.progress = newProgress();
  state.saved = null;
  state.archive = [];
  state.mistakes = [];
  state.difficulty = 'match';
});
afterEach(() => vi.useRealTimers());

describe('game setup', () => {
  it('pass-and-play starts from the initial position with no clock, plan or AI', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    expect(c.game.status).toBe('active');
    expect(c.game.startFen).toBe(START_FEN);
    expect(c.humanTurn()).toBe(true);
    expect(c.clock).toBeNull();
    expect(c.plan).toBeNull();
    expect(c.hintsLeft).toBe(3);
    expect(requestAiMove).not.toHaveBeenCalled();
    expect(state.saved?.mode).toBe('pvp');
    expect(state.saved?.uciMoves).toEqual([]);
  });

  it('bumps gameId for every new game so the UI can reset local state', () => {
    const c = new GameController();
    const g0 = c.gameId;
    c.newGame({ mode: 'pvp' });
    c.newGame({ mode: 'pvp' });
    expect(c.gameId).toBe(g0 + 2);
  });

  it('vs AI builds an adaptation plan and takes its skill from the player model', () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    expect(c.plan).not.toBeNull();
    expect(c.aiSkill).toBe(c.plan!.skill);
    expect(c.aiElo).toBe(c.plan!.aiElo);
    expect(c.humanTurn()).toBe(true);
    expect(requestAiMove).not.toHaveBeenCalled();
  });
});

describe('moves and turns', () => {
  it('records SAN and autosaves the UCI line after every ply', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    play(c, 'e2e4');
    play(c, 'e7e5');
    expect(c.game.sanLine()).toEqual(['e4', 'e5']);
    expect(state.saved?.uciMoves).toEqual(['e2e4', 'e7e5']);
    expect(state.saved?.thinkMs).toHaveLength(2);
  });

  it('rejects illegal moves and moves after the game has ended', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    expect(c.uciToMove('e2e5')).toBeNull();
    c.resign();
    expect(c.playMove(c.game.pos.generateLegal()[0])).toBe(false);
  });

  it('as Black, the AI moves first after a humanlike pause', async () => {
    scriptAi('e2e4');
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: BLACK });
    expect(c.thinking).toBe(true);
    expect(c.humanTurn()).toBe(false);
    expect(requestAiMove).toHaveBeenCalledTimes(1);
    expect(vi.mocked(requestAiMove).mock.calls[0][0].fen).toBe(START_FEN);
    await vi.advanceTimersByTimeAsync(100);
    expect(c.game.history).toHaveLength(0); // still pacing
    await settle();
    expect(c.thinking).toBe(false);
    expect(c.game.sanLine()).toEqual(['e4']);
    expect(c.humanTurn()).toBe(true);
  });

  it("answers the player's move", async () => {
    scriptAi('e7e5');
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    play(c, 'e2e4');
    expect(c.thinking).toBe(true);
    expect(c.humanTurn()).toBe(false);
    await settle();
    expect(c.game.sanLine()).toEqual(['e4', 'e5']);
    expect(c.humanTurn()).toBe(true);
    expect(state.saved?.uciMoves).toEqual(['e2e4', 'e7e5']);
  });

  it('ignores a stale AI reply that arrives after a new game started', async () => {
    let resolveFirst!: (r: MoveResponse) => void;
    vi.mocked(requestAiMove).mockImplementationOnce(() => new Promise<MoveResponse>(r => { resolveFirst = r; }));
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: BLACK });
    scriptAi('d2d4');
    c.newGame({ mode: 'ai', playerColor: BLACK });
    resolveFirst(moveRes('e2e4'));
    await settle();
    expect(c.game.sanLine()).toEqual(['d4']);
  });

  it('plays any legal move if the AI worker fails, so the game never stalls', async () => {
    vi.mocked(requestAiMove).mockRejectedValue(new Error('worker died'));
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: BLACK });
    await settle();
    expect(c.thinking).toBe(false);
    expect(c.game.history).toHaveLength(1);
    expect(c.humanTurn()).toBe(true);
  });
});

describe('takebacks', () => {
  it('are allowed only in casual, untimed, non-challenge games with a move to undo', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    expect(c.takebacksAllowed()).toBe(false);
    play(c, 'e2e4');
    expect(c.takebacksAllowed()).toBe(true);
    state.settings.takebacks = false;
    expect(c.takebacksAllowed()).toBe(false);
    state.settings.takebacks = true;

    c.newGame({ mode: 'pvp', timeControl: TIME_PRESETS[2] });
    play(c, 'e2e4');
    expect(c.takebacksAllowed()).toBe(false);

    c.newGame({ mode: 'puzzle', challenge: { puzzle: PUZZLES[0] } });
    expect(c.takebacksAllowed()).toBe(false);
  });

  it("vs AI, undo rewinds both plies back to the player's turn", async () => {
    scriptAi('e7e5');
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    play(c, 'e2e4');
    await settle();
    expect(c.game.history).toHaveLength(2);
    c.undo();
    expect(c.game.history).toHaveLength(0);
    expect(c.humanTurn()).toBe(true);
    expect(requestAiMove).toHaveBeenCalledTimes(1);
    expect(state.saved?.uciMoves).toEqual([]);
  });

  it('in pass-and-play, undo rewinds one ply', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    play(c, 'e2e4');
    play(c, 'e7e5');
    c.undo();
    expect(c.game.sanLine()).toEqual(['e4']);
  });
});

describe('puzzles', () => {
  const backRank = PUZZLES.find(p => p.id === 'm1-backrank')!;

  it('sets up the puzzle side to move with no hints and a full-strength defender', () => {
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: backRank } });
    expect(c.game.startFen).toBe(backRank.fen);
    expect(c.playerColor).toBe(WHITE);
    expect(c.puzzleState).toBe('solving');
    expect(c.hintsLeft).toBe(0);
    expect(c.aiSkill).toBe(20);
    expect(c.isChallengeGame()).toBe(true);
  });

  it('a mate-in-one is solved by mating; XP is granted once', () => {
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: backRank } });
    play(c, 'a1a8');
    expect(c.puzzleState).toBe('solved');
    expect(c.game.result?.kind).toBe('checkmate');
    expect(state.progress.xp).toBe(backRank.xp);
    expect(state.progress.solvedPuzzles).toEqual([backRank.id]);
    expect(state.progress.counters.puzzlesSolved).toBe(1);
    expect(state.saved).toBeNull();
    // puzzles are not games
    expect(state.progress.counters.gamesPlayed).toBe(0);
    expect(state.archive).toHaveLength(0);

    c.retryPuzzle();
    expect(c.puzzleState).toBe('solving');
    play(c, 'a1a8');
    expect(state.progress.xp).toBe(backRank.xp);
    expect(state.progress.counters.puzzlesSolved).toBe(2);
  });

  it('a non-mating move in a mate-in-one is wrong', () => {
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: backRank } });
    play(c, 'a1a7');
    expect(c.puzzleState).toBe('wrong');
    expect(state.progress.xp).toBe(0);
  });

  it('a tactic only accepts the engine-best move', () => {
    const fork = PUZZLES.find(p => p.id === 't-fork')!;
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: fork } });
    play(c, 'd5e7');
    expect(c.puzzleState).toBe('wrong');
    c.retryPuzzle();
    play(c, fork.solution);
    expect(c.puzzleState).toBe('solved');
  });

  it('a mate-in-two asks the engine whether mate is still forced after the first move', async () => {
    const ladder = PUZZLES.find(p => p.id === 'm2-ladder')!;
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: ladder } });
    vi.mocked(requestHint).mockResolvedValueOnce(hintRes('h8g8', -200_000));
    play(c, ladder.solution);
    await settle();
    expect(c.puzzleState).toBe('solving');
    expect(requestHint).toHaveBeenCalledTimes(1);

    c.retryPuzzle();
    vi.mocked(requestHint).mockResolvedValueOnce(hintRes('h8g8', 0));
    play(c, 'a1a2');
    await settle();
    expect(c.puzzleState).toBe('wrong');
  });

  it('a recorded mistake replays as a personalized puzzle', () => {
    const mistake: RecordedMistake = {
      fen: backRank.fen, playedUci: 'a1a7', bestUci: 'a1a8', cpLoss: 900, date: 0, playerColor: 'w',
    };
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { mistake } });
    expect(c.puzzleState).toBe('solving');
    play(c, 'a1a8');
    expect(c.puzzleState).toBe('solved');
    expect(state.progress.xp).toBe(15);
    expect(state.progress.solvedPuzzles).toEqual([]);
    expect(state.progress.counters.puzzlesSolved).toBe(1);
  });

  it('solving the daily puzzle advances the streak', () => {
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: backRank, isDaily: true } });
    play(c, 'a1a8');
    expect(state.progress.dailyStreak).toBe(1);
    expect(state.progress.lastDailyDate).toBe('2026-06-01');
  });
});

describe('constraint games and drills', () => {
  it('silent queen: the player may not move the queen', () => {
    const sq = CONSTRAINTS.find(c => c.kind === 'silent-queen')!;
    const c = new GameController();
    c.newGame({
      mode: 'constraint', challenge: { constraint: sq },
      startFen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
    });
    expect(c.moveAllowedByConstraint(c.uciToMove('d1h5')!)).toBe(false);
    expect(c.moveAllowedByConstraint(c.uciToMove('g1f3')!)).toBe(true);
    expect(c.hintsLeft).toBe(0);
  });

  it('rook odds starts from the odds position', () => {
    const odds = CONSTRAINTS.find(c => c.kind === 'rook-odds')!;
    const c = new GameController();
    c.newGame({ mode: 'constraint', challenge: { constraint: odds } });
    expect(c.game.pos.toFen()).toBe(odds.fen);
  });

  it("knight's honor completes only when a knight delivers mate", () => {
    const km = CONSTRAINTS.find(c => c.kind === 'knight-mate')!;
    const c = new GameController();
    c.newGame({ mode: 'constraint', challenge: { constraint: km }, startFen: '6rk/6pp/8/6N1/8/8/8/K7 w - - 0 1' });
    play(c, 'g5f7');
    expect(c.game.result?.kind).toBe('checkmate');
    expect(c.game.result?.winner).toBe(WHITE);
    expect(state.progress.completedConstraints).toEqual([km.id]);
    expect(state.progress.xp).toBe(km.xp);
    expect(state.progress.counters.checkmates).toBe(1);
    expect(state.progress.counters.gamesPlayed).toBe(1);
    expect(state.archive).toHaveLength(1);
    expect(state.archive[0].mode).toBe('constraint');

    // the same mate delivered by a rook does not count
    state.progress = newProgress();
    c.newGame({ mode: 'constraint', challenge: { constraint: km }, startFen: '7k/6pp/8/8/8/8/6N1/R6K w - - 0 1' });
    play(c, 'a1a8');
    expect(c.game.result?.kind).toBe('checkmate');
    expect(state.progress.completedConstraints).toEqual([]);
  });

  it('a won drill is completed once and pays its XP', () => {
    const drill: Drill = {
      id: 'test-drill', title: 'Mate the king', fen: '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1',
      playerColor: 'w', goal: 'win', description: '', xp: 30,
    };
    const c = new GameController();
    c.newGame({ mode: 'drill', challenge: { drill } });
    expect(c.aiSkill).toBe(20);
    expect(c.playerColor).toBe(WHITE);
    play(c, 'a1a8');
    expect(state.progress.completedDrills).toEqual(['test-drill']);
    expect(state.progress.xp).toBe(30);
    c.newGame({ mode: 'drill', challenge: { drill } });
    play(c, 'a1a8');
    expect(state.progress.xp).toBe(30);
  });

  it('a drill to hold the draw is satisfied by a draw', () => {
    const drill: Drill = {
      id: 'test-hold', title: 'Hold', fen: '7k/8/6K1/8/8/8/8/5Q2 w - - 0 1',
      playerColor: 'w', goal: 'draw', description: '', xp: 20,
    };
    const c = new GameController();
    c.newGame({ mode: 'drill', challenge: { drill } });
    play(c, 'f1f7');
    expect(c.game.result?.kind).toBe('stalemate');
    expect(state.progress.completedDrills).toEqual(['test-hold']);
    expect(state.progress.xp).toBe(20);
  });
});

describe('ending a game', () => {
  it('resignation vs the AI updates record, rating, XP and the archive', () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    const before = state.model.rating;
    c.resign();
    expect(c.game.status).toBe('finished');
    expect(c.game.result?.kind).toBe('resignation');
    expect(c.game.result?.winner).toBe(BLACK);
    expect(state.progress.counters.gamesPlayed).toBe(1);
    expect(state.progress.counters.gamesWon).toBe(0);
    expect(state.model.losses).toBe(1);
    expect(state.model.rating).toBeLessThan(before);
    expect(state.progress.xp).toBe(10);
    expect(state.archive).toHaveLength(1);
    expect(state.archive[0].score).toBe('0-1');
    expect(state.archive[0].pgn).toContain('[White "You"]');
    expect(state.archive[0].pgn).toContain(`[Black "AI (${c.aiElo})"]`);
    expect(state.saved).toBeNull();
    expect(c.postGame?.offersReady).toBe(true);
    expect(requestAnalysis).not.toHaveBeenCalled(); // too short to analyse

    c.resign(); // idempotent
    expect(state.progress.counters.gamesPlayed).toBe(1);
    expect(state.archive).toHaveLength(1);
  });

  it('pass-and-play: the side on move resigns; draw offers are accepted by the other side', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    play(c, 'e2e4');
    c.offerDraw();
    expect(c.game.drawOffer).toBe(BLACK);
    c.declineDraw();
    expect(c.game.drawOffer).toBeNull();
    c.offerDraw();
    c.acceptDraw();
    expect(c.game.result?.kind).toBe('agreement');
    expect(state.progress.counters.gamesPlayed).toBe(1);
    expect(state.model.draws).toBe(0); // pass-and-play never touches the player model
    expect(state.archive[0].pgn).toContain('[White "White"]');

    c.newGame({ mode: 'pvp' });
    play(c, 'e2e4');
    c.resign();
    expect(c.game.result?.winner).toBe(WHITE);
  });

  it('the AI accepts a draw only when clearly worse', async () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    vi.mocked(requestHint).mockResolvedValueOnce(hintRes('e2e4', 50)); // AI only slightly worse
    c.offerDraw();
    await settle();
    expect(c.game.status).toBe('active');
    expect(c.game.drawOffer).toBeNull();

    vi.mocked(requestHint).mockResolvedValueOnce(hintRes('e2e4', 300)); // AI clearly worse
    c.offerDraw();
    await settle();
    expect(c.game.result?.kind).toBe('agreement');
    expect(state.model.draws).toBe(1);
    expect(state.progress.xp).toBe(20);
  });
});

describe('clocks', () => {
  it('start on the first move, press with increment, and are saved for resume', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp', timeControl: TIME_PRESETS[1] }); // Blitz 3+2
    expect(c.timerOn).toBe(true);
    expect(c.clock!.active).toBeNull();
    play(c, 'e2e4');
    expect(c.clock!.active).toBe(BLACK);
    vi.advanceTimersByTime(3000);
    play(c, 'e7e5');
    expect(c.game.history[1].clockMs).toBe(177_000);
    expect(c.clock!.remaining[BLACK]).toBe(180_000 - 3000 + 2000);
    expect(c.clock!.active).toBe(WHITE);
    expect(state.saved?.clockRemaining).toEqual([180_000, 179_000]);
  });

  it('a flag fall ends the game on time and counts as a win on time', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp', timeControl: TIME_PRESETS[0] }); // Bullet 1+0
    play(c, 'e2e4');
    vi.advanceTimersByTime(61_000);
    expect(c.game.status).toBe('finished');
    expect(c.game.result?.kind).toBe('timeout');
    expect(c.game.result?.winner).toBe(WHITE);
    expect(state.progress.counters.winsOnTime).toBe(1);
    expect(state.progress.badges).toContain('flag-win');
    expect(state.saved).toBeNull();
  });

  it('can be switched off before the first move but not after', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp', timeControl: TIME_PRESETS[2] });
    c.setTimerOn(false);
    expect(c.clock).toBeNull();
    expect(c.timeControl).toBeNull();
    c.newGame({ mode: 'pvp', timeControl: TIME_PRESETS[2] });
    play(c, 'e2e4');
    c.setTimerOn(false);
    expect(c.clock).not.toBeNull();
    expect(c.timerOn).toBe(true);
  });

  it('the AI budgets less thinking time when short on clock', () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE, timeControl: { name: 't', baseMs: 4000, incrementMs: 0 } });
    play(c, 'e2e4');
    const opts = vi.mocked(requestAiMove).mock.calls[0][0];
    expect(opts.moveTimeMs).toBe(150); // max(150, 4000 / 40)
  });
});

describe('resume', () => {
  it('restores position, mode and clocks, then hands the move to the AI', () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE, timeControl: TIME_PRESETS[2] });
    play(c, 'e2e4');
    vi.advanceTimersByTime(1500);
    c.save();
    c.clock!.dispose();
    const saved = JSON.parse(JSON.stringify(state.saved)) as SavedGame;
    expect(saved.clockRemaining).toEqual([600_000, 598_500]);

    const c2 = new GameController();
    expect(c2.resume(saved)).toBe(true);
    expect(c2.game.uciLine()).toEqual(['e2e4']);
    expect(c2.mode).toBe('ai');
    expect(c2.playerColor).toBe(WHITE);
    expect(c2.aiElo).toBe(c.aiElo);
    expect(c2.clock!.remaining).toEqual([600_000, 598_500]);
    expect(c2.clock!.active).toBe(BLACK);
    expect(c2.thinking).toBe(true);
    expect(requestAiMove).toHaveBeenCalledTimes(2);
    c2.clock!.dispose();
  });

  it('restores a challenge by id', () => {
    const backRank = PUZZLES.find(p => p.id === 'm1-backrank')!;
    const c = new GameController();
    c.newGame({ mode: 'puzzle', challenge: { puzzle: backRank } });
    const saved = JSON.parse(JSON.stringify(state.saved)) as SavedGame;
    expect(saved.challengeId).toBe(backRank.id);
    const c2 = new GameController();
    expect(c2.resume(saved)).toBe(true);
    expect(c2.challenge?.puzzle?.id).toBe(backRank.id);
    expect(c2.puzzleState).toBe('solving');
    expect(c2.game.startFen).toBe(backRank.fen);
  });

  it('refuses a corrupted save', () => {
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    const saved = JSON.parse(JSON.stringify(state.saved)) as SavedGame;
    saved.uciMoves = ['e2e4', 'zz99'];
    expect(new GameController().resume(saved)).toBe(false);
  });
});

describe('hints', () => {
  it('cost one of three and come from the engine', async () => {
    vi.mocked(requestHint).mockResolvedValueOnce(hintRes('e2e4', 30));
    const c = new GameController();
    c.newGame({ mode: 'pvp' });
    await c.useHint();
    expect(c.hintsLeft).toBe(2);
    expect(state.progress.counters.hintsUsed).toBe(1);
    expect(moveToUci(c.hintMove!)).toBe('e2e4');
    expect(state.saved?.hintsLeft).toBe(2);
    play(c, 'e2e4');
    expect(c.hintMove).toBeNull();
  });

  it("are unavailable when exhausted or when it is not the human's turn", async () => {
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: BLACK }); // AI to move
    await c.useHint();
    expect(requestHint).not.toHaveBeenCalled();
    c.newGame({ mode: 'pvp' });
    c.hintsLeft = 0;
    await c.useHint();
    expect(requestHint).not.toHaveBeenCalled();
  });
});

describe('post-game analysis', () => {
  it('grades a finished AI game, records big mistakes and attaches the analysis to the archive', async () => {
    scriptAi('e7e5', 'd8h4');
    vi.mocked(requestAnalysis).mockResolvedValueOnce({
      id: 0, type: 'analyze',
      moves: [
        analysed('f2f3', 'e2e4', 60), analysed('e7e5', 'e7e5', 0),
        analysed('g2g4', 'd2d4', 900), analysed('d8h4', 'd8h4', 0),
      ],
    });
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    play(c, 'f2f3');
    await settle();
    play(c, 'g2g4');
    await settle();
    expect(c.game.result?.kind).toBe('checkmate');
    expect(c.game.result?.winner).toBe(BLACK);
    expect(requestAnalysis).toHaveBeenCalledWith(START_FEN, ['f2f3', 'e7e5', 'g2g4', 'd8h4'], 250);
    await settle();
    expect(c.analysisPending).toBe(false);
    expect(c.analysis).toHaveLength(4);
    expect(state.mistakes).toHaveLength(1);
    expect(state.mistakes[0]).toMatchObject({ playedUci: 'g2g4', bestUci: 'd2d4', cpLoss: 900, playerColor: 'w' });
    expect(state.mistakes[0].fen.startsWith('rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w')).toBe(true);
    expect(state.archive[0].analysis).toHaveLength(4);
    expect(state.model.features.avgCpLoss).toBe(480);
    expect(state.model.losses).toBe(1);
    expect(state.progress.xp).toBe(10);
  });

  it('survives an analysis failure', async () => {
    scriptAi('e7e5', 'd8h4');
    vi.mocked(requestAnalysis).mockRejectedValueOnce(new Error('boom'));
    const c = new GameController();
    c.newGame({ mode: 'ai', playerColor: WHITE });
    play(c, 'f2f3');
    await settle();
    play(c, 'g2g4');
    await settle();
    expect(c.game.status).toBe('finished');
    expect(c.analysisPending).toBe(false);
    expect(c.analysis).toBeNull();
    expect(state.archive).toHaveLength(1);
    expect(state.archive[0].analysis).toBeNull();
  });
});
