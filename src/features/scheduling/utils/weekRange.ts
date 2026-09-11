/**
 * Week-grid date math for the Schedule page. A "week" is Monday-to-Monday
 * (exclusive end), independent of the visitor's system locale's first day
 * of week, so the grid is deterministic.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** The Monday (00:00 local) of the week containing `date`. */
export function startOfWeek(date: Date): Date {
  const result = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const day = result.getDay(); // 0 = Sunday, 1 = Monday, ...
  const diffToMonday = day === 0 ? -6 : 1 - day;
  result.setDate(result.getDate() + diffToMonday);
  return result;
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * DAY_MS);
}

export function toDateInputValue(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** The 7 calendar days (Monday-Sunday) of the week containing `date`. */
export function weekDays(date: Date): Date[] {
  const monday = startOfWeek(date);
  return Array.from({ length: 7 }, (_, index) => addDays(monday, index));
}

/** [rangeStart, rangeEnd) as ISO timestamps for a shifts query covering the week containing `date`. */
export function weekRangeIso(date: Date): { rangeStart: string; rangeEnd: string } {
  const monday = startOfWeek(date);
  const nextMonday = addDays(monday, 7);
  return { rangeStart: monday.toISOString(), rangeEnd: nextMonday.toISOString() };
}

export function formatWeekLabel(date: Date): string {
  const monday = startOfWeek(date);
  const sunday = addDays(monday, 6);
  const fmt = (d: Date) => d.toLocaleDateString('en-ZA', { day: '2-digit', month: 'short' });
  return `${fmt(monday)} – ${fmt(sunday)}, ${sunday.getFullYear()}`;
}
