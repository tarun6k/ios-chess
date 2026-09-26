import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  newProgress, levelForXp, refreshBadges, BADGES,
  dailyPuzzle, completeDaily, isDailyDone, offerChallenges,
} from '../src/app/progression';
import { newPlayerModel } from '../src/ai/playerModel';
import { PUZZLES, DRILLS, CONSTRAINTS } from '../src/app/puzzles';

describe('levels', () => {
  it('starts at level 1 needing 100 XP', () => {
    expect(levelForXp(0)).toEqual({ level: 1, into: 0, needed: 100 });
  });

  it('advances with growing thresholds (100, 200, 300 …)', () => {
    expect(levelForXp(99)).toEqual({ level: 1, into: 99, needed: 100 });
    expect(levelForXp(100)).toEqual({ level: 2, into: 0, needed: 200 });
    expect(levelForXp(300)).toEqual({ level: 3, into: 0, needed: 300 });
    expect(levelForXp(599)).toEqual({ level: 3, into: 299, needed: 300 });
    expect(levelForXp(600)).toEqual({ level: 4, into: 0, needed: 400 });
  });
});

describe('badges', () => {
  it('have unique ids', () => {
    const ids = BADGES.map(b => b.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('are awarded once and only the new ones are reported', () => {
    const p = newProgress();
    const m = newPlayerModel();
    expect(refreshBadges(p, m)).toEqual([]);
    p.counters.gamesWon = 1;
    expect(refreshBadges(p, m).map(b => b.id)).toEqual(['first-win']);
    expect(p.badges).toEqual(['first-win']);
    expect(refreshBadges(p, m)).toEqual([]);
  });

  it('rating badges read the player model', () => {
    const p = newProgress();
    const m = newPlayerModel();
    m.rating = 1250;
    expect(refreshBadges(p, m).map(b => b.id)).toEqual(['rating-1200']);
    m.rating = 1650;
    expect(refreshBadges(p, m).map(b => b.id)).toEqual(['rating-1600']);
  });

  it('counter badges fire at their thresholds', () => {
    const p = newProgress();
    const m = newPlayerModel();
    p.counters.puzzlesSolved = 10;
    p.counters.castledGames = 10;
    p.dailyStreak = 7;
    const ids = refreshBadges(p, m).map(b => b.id).sort();
    expect(ids).toEqual(['castle-10', 'puzzle-10', 'streak-3', 'streak-7']);
  });
});

describe('daily challenge', () => {
  afterEach(() => vi.useRealTimers());

  it('is deterministic per calendar day and drawn from the shipped puzzles', () => {
    const a = dailyPuzzle(new Date('2026-03-04T10:00:00Z'));
    const b = dailyPuzzle(new Date('2026-03-04T23:00:00Z'));
    expect(a).toBe(b);
    expect(PUZZLES).toContain(a);
  });

  it('varies across days', () => {
    const seen = new Set<string>();
    for (let d = 1; d <= 31; d++) seen.add(dailyPuzzle(new Date(Date.UTC(2026, 0, d))).id);
    expect(seen.size).toBeGreaterThan(1);
  });

  it('builds a streak on consecutive days and resets after a gap', () => {
    vi.useFakeTimers();
    const p = newProgress();

    vi.setSystemTime(new Date('2026-05-01T12:00:00Z'));
    expect(isDailyDone(p)).toBe(false);
    completeDaily(p);
    expect(p.dailyStreak).toBe(1);
    expect(p.lastDailyDate).toBe('2026-05-01');
    expect(isDailyDone(p)).toBe(true);

    completeDaily(p); // same day again is a no-op
    expect(p.dailyStreak).toBe(1);

    vi.setSystemTime(new Date('2026-05-02T12:00:00Z'));
    expect(isDailyDone(p)).toBe(false);
    completeDaily(p);
    expect(p.dailyStreak).toBe(2);

    vi.setSystemTime(new Date('2026-05-04T12:00:00Z')); // skipped the 3rd
    completeDaily(p);
    expect(p.dailyStreak).toBe(1);
  });
});

describe('offerChallenges', () => {
  it('falls back to the first unfinished constraint game when nothing is targetable', () => {
    const offers = offerChallenges(newPlayerModel(), newProgress(), null);
    expect(offers).toHaveLength(1);
    expect(offers[0].kind).toBe('constraint');
    expect(offers[0].constraintId).toBe(CONSTRAINTS[0].id);
  });

  it('targets the top weakness with a set of shipped puzzles', () => {
    const m = newPlayerModel();
    m.weaknesses['hanging-pieces'] = 3;
    const set = offerChallenges(m, newProgress(), null).find(o => o.kind === 'puzzle-set');
    expect(set).toBeDefined();
    expect(set!.puzzleIds!.length).toBeGreaterThan(0);
    for (const id of set!.puzzleIds!) expect(PUZZLES.some(p => p.id === id)).toBe(true);
    expect(set!.xp).toBe(set!.puzzleIds!.length * 10);
    expect(set!.detail).toContain('leaving pieces undefended');
  });

  it('prescribes the first unfinished drill for an endgame weakness', () => {
    const m = newPlayerModel();
    m.weaknesses.endgame = 2;
    const p = newProgress();
    p.completedDrills.push(DRILLS[0].id);
    const drill = offerChallenges(m, p, null).find(o => o.kind === 'drill');
    expect(drill?.drillId).toBe(DRILLS[1].id);
    expect(drill?.xp).toBe(DRILLS[1].xp);
  });

  it('offers a timed blitz rematch after a real game, worded by the outcome', () => {
    const win = offerChallenges(newPlayerModel(), newProgress(), true).find(o => o.kind === 'rematch-blitz')!;
    const loss = offerChallenges(newPlayerModel(), newProgress(), false).find(o => o.kind === 'rematch-blitz')!;
    expect(win.title).toBe('Prove it');
    expect(loss.title).toBe('Redemption');
    expect(win.timed).toBe(true);
  });

  it('never offers more than three and skips completed constraints', () => {
    const m = newPlayerModel();
    m.weaknesses['hanging-pieces'] = 3;
    m.weaknesses['back-rank'] = 2;
    const p = newProgress();
    p.completedConstraints.push(CONSTRAINTS[0].id);
    const offers = offerChallenges(m, p, true);
    expect(offers.length).toBeLessThanOrEqual(3);
    expect(offers.filter(o => o.kind === 'puzzle-set')).toHaveLength(2);
    expect(offers.map(o => o.constraintId)).not.toContain(CONSTRAINTS[0].id);

    const onlyConstraint = offerChallenges(newPlayerModel(), p, null);
    expect(onlyConstraint[0].constraintId).toBe(CONSTRAINTS[1].id);
  });
});
