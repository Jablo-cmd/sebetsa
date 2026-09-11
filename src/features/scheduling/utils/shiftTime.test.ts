import { describe, expect, it } from 'vitest';
import { resolveShiftTimestamps, splitTimestamp } from '@/features/scheduling/utils/shiftTime';

describe('resolveShiftTimestamps', () => {
  it('resolves a same-day shift to the same calendar date', () => {
    const { startsAt, endsAt } = resolveShiftTimestamps('2026-09-15', '08:00', '17:00', false);
    const start = new Date(startsAt);
    const end = new Date(endsAt);
    expect(start.getDate()).toBe(15);
    expect(end.getDate()).toBe(15);
    expect(end.getTime()).toBeGreaterThan(start.getTime());
  });

  it('rolls the end time to the next calendar day when endsNextDay is set', () => {
    const { startsAt, endsAt } = resolveShiftTimestamps('2026-09-15', '22:00', '06:00', true);
    const start = new Date(startsAt);
    const end = new Date(endsAt);
    expect(start.getDate()).toBe(15);
    expect(end.getDate()).toBe(16);
    expect(end.getTime()).toBeGreaterThan(start.getTime());
  });
});

describe('splitTimestamp', () => {
  it('round-trips a resolved timestamp back to date + time', () => {
    const { startsAt } = resolveShiftTimestamps('2026-09-15', '08:30', '17:00', false);
    const { date, time } = splitTimestamp(startsAt);
    expect(date).toBe('2026-09-15');
    expect(time).toBe('08:30');
  });
});
