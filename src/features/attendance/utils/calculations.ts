import type { AttendanceRecord, AttendanceStatusCounts } from '@/features/attendance/types/attendance.types';

/**
 * Centralized attendance calculations — every component that needs a
 * count breakdown or a percentage goes through here, matching the
 * assessments feature's own "do not duplicate calculation logic
 * throughout the UI" convention (src/features/assessments/utils/calculations.ts).
 *
 * ATTENDANCE PERCENTAGE — DEFINITION (nothing in the existing schema or
 * implementation defined this before now, so it is stated explicitly and
 * applied consistently everywhere a rate is shown):
 *
 *   attendance rate = (present + late) / (present + late + absent) × 100
 *
 * "Excused" days are deliberately excluded from BOTH the numerator and the
 * denominator — an excused absence (a medical note, approved leave) is not
 * held against the learner, matching how real school attendance policy
 * treats it, but it also isn't "attendance" the way Present/Late are. A
 * day with no attendance_records row at all (never marked) is likewise
 * excluded — it was never a "qualifying recorded school day" per the
 * brief's own formula, so it neither helps nor hurts the rate.
 *
 * Rounding rule (same split assessments/calculations.ts uses, for the same
 * reason): a single learner's or single class's rate rounds to a whole
 * number (e.g. "84%") when it stands alone as one figure someone reads at
 * a glance; an aggregate/average across many learners or classes rounds to
 * one decimal place, since it's a computed statistic rather than a literal
 * count.
 */

export interface AttendanceStats extends AttendanceStatusCounts {
  /** present + late + absent — the "qualifying recorded school days" the rate is computed over. Excludes excused and un-marked days. */
  qualifyingDays: number;
  /** null when qualifyingDays is 0 — never render a rate for a learner/class with nothing to compute it from. */
  attendanceRate: number | null;
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/** Tallies raw status counts into a StatusCounts object — the one place `for (const row of records) counts[row.status] += 1` is written. */
export function tallyStatusCounts(records: { status: AttendanceRecord['status'] }[]): AttendanceStatusCounts {
  const counts: AttendanceStatusCounts = { present: 0, absent: 0, late: 0, excused: 0, unconfirmed: 0 };
  for (const record of records) counts[record.status] += 1;
  return counts;
}

/** The attendance rate for one set of counts, per the definition above. Rounds to a whole number — use for a single learner or a single class. */
export function calculateAttendanceRate(counts: AttendanceStatusCounts): number | null {
  const qualifyingDays = counts.present + counts.late + counts.absent;
  if (qualifyingDays === 0) return null;
  return round(((counts.present + counts.late) / qualifyingDays) * 100, 0);
}

/** Full stats (counts + qualifying-day total + rate) from a set of raw attendance records — the shape every report row and summary card is built from. */
export function calculateAttendanceStats(records: { status: AttendanceRecord['status'] }[]): AttendanceStats {
  const counts = tallyStatusCounts(records);
  const qualifyingDays = counts.present + counts.late + counts.absent;
  return {
    ...counts,
    qualifyingDays,
    attendanceRate: calculateAttendanceRate(counts),
  };
}

/** An aggregate rate across multiple already-computed per-learner/per-class rates (e.g. a school-wide average) — rounds to one decimal, per the rule above. Learners/classes with a null rate (no qualifying days) are excluded, not treated as 0. */
export function calculateAverageRate(rates: (number | null)[]): number | null {
  const known = rates.filter((rate): rate is number => rate !== null);
  if (known.length === 0) return null;
  return round(known.reduce((sum, rate) => sum + rate, 0) / known.length, 1);
}
