import { describe, expect, it } from 'vitest';
import { calendarDays, workingDays } from '@/features/leave/utils/duration';

describe('calendarDays', () => {
  it('counts inclusively', () => {
    expect(calendarDays('2026-09-14', '2026-09-16', false)).toBe(3);
  });

  it('is 1 for a single day', () => {
    expect(calendarDays('2026-09-14', '2026-09-14', false)).toBe(1);
  });

  it('is 0.5 for a half day regardless of range', () => {
    expect(calendarDays('2026-09-14', '2026-09-14', true)).toBe(0.5);
  });
});

describe('workingDays', () => {
  it('excludes weekends within the range', () => {
    // 2026-09-14 is a Monday; 2026-09-18 is a Friday; +2 weekend days follow.
    expect(workingDays('2026-09-14', '2026-09-20', false)).toBe(5);
  });

  it('counts a single weekday as 1', () => {
    expect(workingDays('2026-09-14', '2026-09-14', false)).toBe(1);
  });

  it('counts a single weekend day as 0', () => {
    // 2026-09-19 is a Saturday.
    expect(workingDays('2026-09-19', '2026-09-19', false)).toBe(0);
  });

  it('is 0.5 for a half day regardless of range', () => {
    expect(workingDays('2026-09-14', '2026-09-14', true)).toBe(0.5);
  });
});
