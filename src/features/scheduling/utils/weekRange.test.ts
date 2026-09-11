import { describe, expect, it } from 'vitest';
import { startOfWeek, addDays, weekDays, weekRangeIso, formatWeekLabel } from '@/features/scheduling/utils/weekRange';

describe('startOfWeek', () => {
  it('returns the same Monday for a Wednesday mid-week', () => {
    const wednesday = new Date(2026, 8, 16); // 2026-09-16 is a Wednesday
    expect(startOfWeek(wednesday).toDateString()).toBe(new Date(2026, 8, 14).toDateString());
  });

  it('rolls a Sunday back to the preceding Monday, not forward', () => {
    const sunday = new Date(2026, 8, 20); // 2026-09-20 is a Sunday
    expect(startOfWeek(sunday).toDateString()).toBe(new Date(2026, 8, 14).toDateString());
  });

  it('is idempotent for a Monday', () => {
    const monday = new Date(2026, 8, 14);
    expect(startOfWeek(monday).toDateString()).toBe(monday.toDateString());
  });
});

describe('weekDays', () => {
  it('returns 7 consecutive days starting on Monday', () => {
    const days = weekDays(new Date(2026, 8, 16));
    expect(days).toHaveLength(7);
    expect(days[0]?.getDay()).toBe(1);
    expect(days[6]?.getDay()).toBe(0);
  });
});

describe('weekRangeIso', () => {
  it('produces a 7-day, half-open range', () => {
    const { rangeStart, rangeEnd } = weekRangeIso(new Date(2026, 8, 16));
    const diffDays = (new Date(rangeEnd).getTime() - new Date(rangeStart).getTime()) / (24 * 60 * 60 * 1000);
    expect(diffDays).toBe(7);
  });
});

describe('addDays', () => {
  it('adds calendar days', () => {
    const base = new Date(2026, 8, 14);
    expect(addDays(base, 3).toDateString()).toBe(new Date(2026, 8, 17).toDateString());
  });
});

describe('formatWeekLabel', () => {
  it('formats a Monday-Sunday range spanning both endpoints and the year', () => {
    const label = formatWeekLabel(new Date(2026, 8, 16));
    expect(label).toContain('14');
    expect(label).toContain('20');
    expect(label).toContain('2026');
    expect(label).toMatch(/–/);
  });
});
