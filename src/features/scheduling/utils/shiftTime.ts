/**
 * Resolves a shift form's date + wall-clock times into the timestamptz
 * pair `shifts.starts_at`/`ends_at` expect. Values are interpreted as
 * South African local time (see the Phase G date/time strategy — no stored
 * timezone; SAST has no DST) using the browser's local clock, which is
 * correct for this single-region MVP.
 */
export function resolveShiftTimestamps(
  date: string,
  startTime: string,
  endTime: string,
  endsNextDay: boolean,
): { startsAt: string; endsAt: string } {
  const [year, month, day] = date.split('-').map(Number);
  const [startHour, startMinute] = startTime.split(':').map(Number);
  const [endHour, endMinute] = endTime.split(':').map(Number);

  const starts = new Date(year ?? 0, (month ?? 1) - 1, day ?? 1, startHour ?? 0, startMinute ?? 0);
  const ends = new Date(year ?? 0, (month ?? 1) - 1, day ?? 1, endHour ?? 0, endMinute ?? 0);
  if (endsNextDay) ends.setDate(ends.getDate() + 1);

  return { startsAt: starts.toISOString(), endsAt: ends.toISOString() };
}

/** Splits an ISO timestamp back into a `YYYY-MM-DD` date and `HH:MM` time, in local time, for populating an edit form. */
export function splitTimestamp(iso: string): { date: string; time: string } {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return {
    date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    time: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
  };
}
