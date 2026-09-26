import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ChessClock, TIME_PRESETS, customTimeControl, formatClock } from '../src/app/clock';
import { WHITE, BLACK } from '../src/engine/types';

describe('ChessClock', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('initialises from the control, honouring per-side overrides', () => {
    const c = new ChessClock({ name: 't', baseMs: 60_000, incrementMs: 1000, blackBaseMs: 30_000 });
    expect(c.remaining).toEqual([60_000, 30_000]);
    expect(c.increment).toBe(1000);
    expect(c.active).toBeNull();
  });

  it('start() drains only the given side, by wall-clock time', () => {
    const c = new ChessClock(TIME_PRESETS[1]); // Blitz 3+2
    c.start(WHITE);
    vi.advanceTimersByTime(1500);
    expect(c.remaining[WHITE]).toBe(180_000 - 1500);
    expect(c.remaining[BLACK]).toBe(180_000);
    c.dispose();
  });

  it('press() awards the increment to the mover and switches sides', () => {
    const c = new ChessClock(TIME_PRESETS[1]);
    c.start(WHITE);
    vi.advanceTimersByTime(5000);
    c.press(WHITE);
    expect(c.remaining[WHITE]).toBe(180_000 - 5000 + 2000);
    expect(c.active).toBe(BLACK);
    vi.advanceTimersByTime(1000);
    expect(c.remaining[BLACK]).toBe(179_000);
    expect(c.remaining[WHITE]).toBe(177_000);
    c.dispose();
  });

  it('press() by the side not on move awards no increment', () => {
    const c = new ChessClock(TIME_PRESETS[1]);
    c.start(WHITE);
    c.press(BLACK);
    expect(c.remaining[BLACK]).toBe(180_000);
    expect(c.active).toBe(WHITE);
    c.dispose();
  });

  it('pause() freezes both sides until start() is called again', () => {
    const c = new ChessClock(TIME_PRESETS[2]); // Rapid 10+0
    c.start(BLACK);
    vi.advanceTimersByTime(2000);
    c.pause();
    vi.advanceTimersByTime(10_000);
    expect(c.remaining[BLACK]).toBe(598_000);
    expect(c.active).toBeNull();
    c.start(BLACK);
    vi.advanceTimersByTime(1000);
    expect(c.remaining[BLACK]).toBe(597_000);
    c.dispose();
  });

  it('ticks the display callback every 100ms while running', () => {
    const c = new ChessClock(TIME_PRESETS[2]);
    const tick = vi.fn();
    c.onTick = tick;
    c.start(WHITE);
    vi.advanceTimersByTime(1000);
    expect(tick).toHaveBeenCalledTimes(10);
    c.pause();
    vi.advanceTimersByTime(1000);
    expect(tick).toHaveBeenCalledTimes(10);
  });

  it('warns exactly once when a side drops to 20 seconds', () => {
    const c = new ChessClock({ name: 't', baseMs: 25_000, incrementMs: 0 });
    const low = vi.fn();
    c.onLowTime = low;
    c.start(WHITE);
    vi.advanceTimersByTime(4900);
    expect(low).not.toHaveBeenCalled();
    vi.advanceTimersByTime(200);
    expect(low).toHaveBeenCalledTimes(1);
    expect(low).toHaveBeenCalledWith(WHITE);
    vi.advanceTimersByTime(3000);
    expect(low).toHaveBeenCalledTimes(1);
    c.dispose();
  });

  it('flags at zero: clamps, stops the timer, fires onFlag once', () => {
    const c = new ChessClock({ name: 't', baseMs: 1000, incrementMs: 0 });
    const flag = vi.fn();
    c.onFlag = flag;
    c.start(BLACK);
    vi.advanceTimersByTime(1500);
    expect(c.remaining[BLACK]).toBe(0);
    expect(c.active).toBeNull();
    expect(flag).toHaveBeenCalledTimes(1);
    expect(flag).toHaveBeenCalledWith(BLACK);
    vi.advanceTimersByTime(1000);
    expect(flag).toHaveBeenCalledTimes(1);
    expect(c.remaining[WHITE]).toBe(1000);
  });

  it('dispose() stops ticking', () => {
    const c = new ChessClock(TIME_PRESETS[0]);
    const tick = vi.fn();
    c.onTick = tick;
    c.start(WHITE);
    c.dispose();
    vi.advanceTimersByTime(1000);
    expect(tick).not.toHaveBeenCalled();
  });
});

describe('time controls', () => {
  it('ships five named presets', () => {
    expect(TIME_PRESETS.map(t => t.name)).toEqual([
      'Bullet 1+0', 'Blitz 3+2', 'Rapid 10+0', 'Rapid 15+10', 'Classical 30+0',
    ]);
  });

  it('builds a custom control in ms', () => {
    expect(customTimeControl(3, 2)).toEqual({ name: 'Custom 3+2', baseMs: 180_000, incrementMs: 2000 });
  });

  it('clamps and rounds custom values', () => {
    expect(customTimeControl(0, -5)).toEqual({ name: 'Custom 1+0', baseMs: 60_000, incrementMs: 0 });
    expect(customTimeControl(500, 999)).toEqual({ name: 'Custom 120+60', baseMs: 7_200_000, incrementMs: 60_000 });
    expect(customTimeControl(2.6, 1.4)).toEqual({ name: 'Custom 3+1', baseMs: 180_000, incrementMs: 1000 });
  });
});

describe('formatClock', () => {
  it('shows hours when at or above one hour', () => {
    expect(formatClock(3_600_000)).toBe('1:00:00');
    expect(formatClock(5_025_000)).toBe('1:23:45');
  });

  it('shows m:ss, rounding partial seconds up', () => {
    expect(formatClock(600_000)).toBe('10:00');
    expect(formatClock(59_400)).toBe('1:00');
    expect(formatClock(20_000)).toBe('0:20');
  });

  it('shows tenths under 20 seconds', () => {
    expect(formatClock(19_950)).toBe('0:19.9');
    expect(formatClock(5_040)).toBe('0:05.0');
    expect(formatClock(0)).toBe('0:00.0');
  });
});
