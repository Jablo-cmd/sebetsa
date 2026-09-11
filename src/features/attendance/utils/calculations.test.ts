import { describe, expect, it } from 'vitest';
import {
  tallyStatusCounts,
  calculateAttendanceRate,
  calculateAttendanceStats,
  calculateAverageRate,
} from './calculations';

describe('tallyStatusCounts', () => {
  it('counts each status independently, including zero counts for statuses not present', () => {
    expect(
      tallyStatusCounts([{ status: 'present' }, { status: 'present' }, { status: 'absent' }, { status: 'late' }]),
    ).toEqual({ present: 2, absent: 1, late: 1, excused: 0, unconfirmed: 0 });
  });

  it('returns all-zero counts for an empty record set', () => {
    expect(tallyStatusCounts([])).toEqual({ present: 0, absent: 0, late: 0, excused: 0, unconfirmed: 0 });
  });
});

describe('calculateAttendanceRate', () => {
  it('returns 100 when every qualifying day was present', () => {
    expect(calculateAttendanceRate({ present: 10, absent: 0, late: 0, excused: 0, unconfirmed: 0 })).toBe(100);
  });

  it('returns 0 when every qualifying day was absent', () => {
    expect(calculateAttendanceRate({ present: 0, absent: 5, late: 0, excused: 0, unconfirmed: 0 })).toBe(0);
  });

  it('counts late as attended, matching present', () => {
    // 8 present + 2 late = 10 attended out of 10 qualifying days
    expect(calculateAttendanceRate({ present: 8, absent: 0, late: 2, excused: 0, unconfirmed: 0 })).toBe(100);
  });

  it('excludes excused days from both the numerator and the denominator', () => {
    // 4 present out of (4 present + 1 absent) = 80%, not diluted by the 3 excused days
    expect(calculateAttendanceRate({ present: 4, absent: 1, late: 0, excused: 3, unconfirmed: 0 })).toBe(80);
  });

  it('rounds to the nearest whole number', () => {
    // 2 attended / 3 qualifying = 66.67% -> 67
    expect(calculateAttendanceRate({ present: 2, absent: 1, late: 0, excused: 0, unconfirmed: 0 })).toBe(67);
  });

  it('returns null when there are no qualifying days at all (nothing recorded, or only excused)', () => {
    expect(calculateAttendanceRate({ present: 0, absent: 0, late: 0, excused: 0, unconfirmed: 0 })).toBeNull();
    expect(calculateAttendanceRate({ present: 0, absent: 0, late: 0, excused: 5, unconfirmed: 0 })).toBeNull();
  });
});

describe('calculateAttendanceStats', () => {
  it('derives counts, qualifyingDays, and rate from raw records in one pass', () => {
    const records = [
      { status: 'present' as const },
      { status: 'present' as const },
      { status: 'late' as const },
      { status: 'absent' as const },
      { status: 'excused' as const },
    ];
    expect(calculateAttendanceStats(records)).toEqual({
      present: 2,
      late: 1,
      absent: 1,
      excused: 1,
      unconfirmed: 0,
      qualifyingDays: 4,
      attendanceRate: 75, // (2 present + 1 late) / 4 qualifying = 75%
    });
  });

  it('handles an empty record set without dividing by zero', () => {
    expect(calculateAttendanceStats([])).toEqual({
      present: 0,
      late: 0,
      absent: 0,
      excused: 0,
      unconfirmed: 0,
      qualifyingDays: 0,
      attendanceRate: null,
    });
  });
});

describe('calculateAverageRate', () => {
  it('averages known rates and rounds to one decimal', () => {
    // (90 + 80 + 70) / 3 = 80
    expect(calculateAverageRate([90, 80, 70])).toBe(80);
    // (100 + 67) / 2 = 83.5
    expect(calculateAverageRate([100, 67])).toBe(83.5);
  });

  it('excludes null rates rather than treating them as zero', () => {
    // A learner/class with no qualifying days must not drag the average down to look like 0% attendance
    expect(calculateAverageRate([100, null, 50])).toBe(75);
  });

  it('returns null when every input rate is null', () => {
    expect(calculateAverageRate([null, null])).toBeNull();
  });

  it('returns null for an empty input array', () => {
    expect(calculateAverageRate([])).toBeNull();
  });
});
