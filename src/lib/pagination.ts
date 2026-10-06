/**
 * PostgREST caps an unranged `.select()` at
 * `[api].max_rows` (1000 in supabase/config.toml) — silently, with no
 * error, no truncation flag. A plain `await query` in a service that
 * aggregates a whole table's worth of rows for a report (attendance over
 * a date range, a tenant's full task history) is therefore not a bug until
 * a tenant's data crosses that row count, at which point the report
 * quietly under-counts. Pages through `.range()` until a page comes back
 * short, accumulating every row, so callers doing report-scale
 * aggregation never have to reason about the cap themselves.
 *
 * Deliberately NOT used for user-facing paginated lists (Employees,
 * Users, Sites, …) — those want exactly one page per request by
 * design; this is only for "I need the true complete set" call sites.
 *
 * Deliberately its own module, not part of src/lib/supabase.ts: that
 * module constructs the live Supabase client (with auth-token
 * auto-refresh side effects) at import time, which is unsafe to pull
 * into a plain unit test under Vitest's `node` environment — this
 * function needs no client of its own (callers supply their own query),
 * so it has no reason to carry that import.
 */
export async function fetchAllRows<T>(
  queryPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  pageSize = 1000,
): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  for (;;) {
    const to = from + pageSize - 1;
    const { data, error } = await queryPage(from, to);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all.push(...data);
    if (data.length < pageSize) break;
    from += pageSize;
  }
  return all;
}
