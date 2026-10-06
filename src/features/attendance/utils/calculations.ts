import type { AttendanceRecord, AttendanceStatusCounts } from '@/features/attendance/types/attendance.types';

/**
 * Centralised workforce attendance calculations — every component that
 * needs a status breakdown or an attendance percentage goes through here.
 *
 * ATTENDANCE RATE — DEFINITION (applied consistently everywhere a rate is
 * shown):
 *
 *   attendance rate = (present + late) / (present + late + absent) × 100
 *
 * "Excused" shifts (approved leave, an approved absence) are excluded from
 * BOTH numerator and denominator — they are not held against the employee,
 * but they are not attendance either. "Unconfirmed" records (no clock-in
 * yet / not reconciled) are likewise excluded until they are resolved.
 *
 * Rounding: a single employee's or single site's rate rounds to a whole
 * number (e.g. "84%"); an aggregate/average across many employees or sites
 * rounds to one decimal place, since it is a computed statistic.
 */

export interface AttendanceStats extends AttendanceStatusCounts {
  /** present + late + absent — the qualifying scheduled shifts the rate is computed over. Excludes excused and un-marked days. */
  qualifyingDays: number;
  /** null when qualifyingDays is 0 — never render a rate for an employee/site with nothing to compute it from. */
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

/** The attendance rate for one set of counts, per the definition above. Rounds to a whole number — use for a single employee or a single site. */
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

/** An aggregate rate across multiple already-computed per-employee/per-site rates (e.g. an organisation-wide average) — rounds to one decimal, per the rule above. Employees/sites with a null rate (no qualifying days) are excluded, not treated as 0. */
export function calculateAverageRate(rates: (number | null)[]): number | null {
  const known = rates.filter((rate): rate is number => rate !== null);
  if (known.length === 0) return null;
  return round(known.reduce((sum, rate) => sum + rate, 0) / known.length, 1);
}
