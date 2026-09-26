import { describe, it, expect, vi, beforeEach } from 'vitest';

// Node has no localStorage; give the storage layer an in-memory one.
class MemoryStorage {
  private m = new Map<string, string>();
  getItem(k: string): string | null { return this.m.has(k) ? this.m.get(k)! : null; }
  setItem(k: string, v: string): void { this.m.set(k, String(v)); }
  removeItem(k: string): void { this.m.delete(k); }
  clear(): void { this.m.clear(); }
  get length(): number { return this.m.size; }
  key(i: number): string | null { return [...this.m.keys()][i] ?? null; }
}
(globalThis as unknown as { localStorage: MemoryStorage }).localStorage = new MemoryStorage();

vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => false } }));
vi.mock('@capacitor/preferences', () => ({ Preferences: {} }));

import { loadKey, saveKey, removeKey } from '../src/app/storage';
import {
  state, loadAll, persist, recordMistakes, DEFAULT_SETTINGS, SavedGame, ArchivedGame, RecordedMistake,
} from '../src/app/store';
import { newProgress } from '../src/app/progression';
import { newPlayerModel } from '../src/ai/playerModel';
import { START_FEN } from '../src/engine/position';

function resetState(): void {
  state.settings = { ...DEFAULT_SETTINGS };
  state.model = newPlayerModel();
  state.progress = newProgress();
  state.saved = null;
  state.archive = [];
  state.mistakes = [];
  state.difficulty = 'match';
  state.playerName = null;
  state.guest = false;
}

const savedGame = (): SavedGame => ({
  mode: 'ai', startFen: START_FEN, uciMoves: ['e2e4'], thinkMs: [1200], playerColor: 'w',
  difficulty: 'match', timeControl: null, clockRemaining: null, timerOn: false, hintsLeft: 3,
  challengeId: null, adaptationNotes: [], aiSkill: 8, aiElo: 1000, savedAt: 1,
});

const archived = (i: number): ArchivedGame => ({
  pgn: '', mode: 'ai', playerColor: 'w', result: '', score: '*', aiElo: null, date: i,
  analysis: null, adaptationNotes: [], startFen: START_FEN, uciMoves: [],
});

const mistake = (i: number): RecordedMistake => ({
  fen: START_FEN, playedUci: 'a2a3', bestUci: 'e2e4', cpLoss: 300, date: i, playerColor: 'w',
});

beforeEach(() => {
  localStorage.clear();
  resetState();
});

describe('storage', () => {
  it('round-trips JSON values and removes keys', async () => {
    await saveKey('k', { a: 1, b: [true] });
    expect(await loadKey('k')).toEqual({ a: 1, b: [true] });
    await removeKey('k');
    expect(await loadKey('k')).toBeNull();
  });

  it('treats missing and corrupt values as absent', async () => {
    expect(await loadKey('nothing')).toBeNull();
    localStorage.setItem('bad', '{not json');
    expect(await loadKey('bad')).toBeNull();
  });
});

describe('store', () => {
  it('loads defaults from empty storage', async () => {
    await loadAll();
    expect(state.settings).toEqual(DEFAULT_SETTINGS);
    expect(state.model.rating).toBe(800);
    expect(state.progress.xp).toBe(0);
    expect(state.saved).toBeNull();
    expect(state.archive).toEqual([]);
    expect(state.difficulty).toBe('match');
    expect(state.playerName).toBeNull();
    expect(state.guest).toBe(false);
  });

  it('merges partial persisted settings over the defaults', async () => {
    localStorage.setItem('chess.settings', JSON.stringify({ sounds: false }));
    await loadAll();
    expect(state.settings.sounds).toBe(false);
    expect(state.settings.coordinates).toBe(true);
  });

  it('fills in fields missing from an older progress record', async () => {
    localStorage.setItem('chess.progress', JSON.stringify({
      xp: 120, badges: ['first-win'], counters: { gamesPlayed: 3 },
    }));
    await loadAll();
    expect(state.progress.xp).toBe(120);
    expect(state.progress.badges).toEqual(['first-win']);
    expect(state.progress.counters.gamesPlayed).toBe(3);
    expect(state.progress.counters.hintsUsed).toBe(0);
    expect(state.progress.completedDrills).toEqual([]);
  });

  it('fills in fields missing from an older player model', async () => {
    localStorage.setItem('chess.playerModel', JSON.stringify({ version: 1, rating: 1234 }));
    await loadAll();
    expect(state.model.rating).toBe(1234);
    expect(state.model.weaknesses['back-rank']).toBe(0);
    expect(state.model.openings).toEqual([]);
  });

  it('persists and reloads the player name, guest choice and difficulty', async () => {
    state.playerName = 'Ada';
    state.guest = true;
    state.difficulty = 'challenge';
    await Promise.all([persist.playerName(), persist.guest(), persist.difficulty()]);
    resetState();
    await loadAll();
    expect(state.playerName).toBe('Ada');
    expect(state.guest).toBe(true);
    expect(state.difficulty).toBe('challenge');
  });

  it('removes the player name key when it is cleared', async () => {
    state.playerName = 'Ada';
    await persist.playerName();
    expect(localStorage.getItem('chess.playerName')).not.toBeNull();
    state.playerName = null;
    await persist.playerName();
    expect(localStorage.getItem('chess.playerName')).toBeNull();
  });

  it('stores the in-flight game and clears the key when there is nothing to resume', async () => {
    state.saved = savedGame();
    await persist.saved();
    resetState();
    await loadAll();
    expect(state.saved?.uciMoves).toEqual(['e2e4']);
    state.saved = null;
    await persist.saved();
    expect(localStorage.getItem('chess.savedGame')).toBeNull();
  });

  it('caps the archive at 100 games on disk', async () => {
    state.archive = Array.from({ length: 130 }, (_, i) => archived(i));
    await persist.archive();
    expect(JSON.parse(localStorage.getItem('chess.archive')!)).toHaveLength(100);
  });

  it('keeps the newest 60 recorded mistakes, newest first', () => {
    recordMistakes(Array.from({ length: 50 }, (_, i) => mistake(i)));
    recordMistakes(Array.from({ length: 20 }, (_, i) => mistake(100 + i)));
    expect(state.mistakes).toHaveLength(60);
    expect(state.mistakes[0].date).toBe(100);
    expect(state.mistakes[19].date).toBe(119);
    expect(state.mistakes[20].date).toBe(0);
  });
});
