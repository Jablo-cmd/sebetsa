/**
 * Client-side preview only — the database RPCs are authoritative (see
 * leave_request_duration_days() and workingDays' server-side equivalent is
 * intentionally NOT enforced server-side per the Phase H architecture:
 * working-day exclusion is a UI preview, not a blocking rule). Never trust
 * these for anything that affects a balance — submit_leave_request always
 * recomputes calendar/half-day duration itself.
 */

function parseIsoDate(iso: string): Date {
  const parts = iso.split('-').map(Number);
  const year = parts[0] ?? 0;
  const month = parts[1] ?? 1;
  const day = parts[2] ?? 1;
  return new Date(Date.UTC(year, month - 1, day));
}

/** Inclusive calendar-day count between two ISO dates (or 0.5 for a half-day request). */
export function calendarDays(startDate: string, endDate: string, isHalfDay: boolean): number {
  if (isHalfDay) return 0.5;
  const start = parseIsoDate(startDate);
  const end = parseIsoDate(endDate);
  const diffMs = end.getTime() - start.getTime();
  return Math.round(diffMs / (1000 * 60 * 60 * 24)) + 1;
}

/** Calendar days excluding Saturday/Sunday — no public-holiday exclusion (Phase H scope). */
export function workingDays(startDate: string, endDate: string, isHalfDay: boolean): number {
  if (isHalfDay) return 0.5;
  const start = parseIsoDate(startDate);
  const end = parseIsoDate(endDate);
  let count = 0;
  for (let d = new Date(start); d.getTime() <= end.getTime(); d.setUTCDate(d.getUTCDate() + 1)) {
    const day = d.getUTCDay();
    if (day !== 0 && day !== 6) count += 1;
  }
  return count;
}
