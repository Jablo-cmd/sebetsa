/**
 * Translates a thrown Supabase/PostgREST error into copy safe to show end
 * users, instead of the raw table/column/constraint text Postgres returns
 * (e.g. `duplicate key value violates unique constraint "learners_school_id_learner_number_key"`).
 * Always logs the original error so developers keep full detail in the
 * console. Falls back to `fallback` for anything unrecognized, and to a
 * plain Error's own message for non-database errors (e.g. network
 * failures) — matching the previous `error instanceof Error ? error.message
 * : fallback` behaviour used across the app for those cases. Authentication
 * errors are unaffected — they go through authErrors.ts, not this.
 */

interface PostgrestLikeError {
  message: string;
  code?: string;
}

function isPostgrestLikeError(error: unknown): error is PostgrestLikeError {
  return (
    typeof error === 'object' &&
    error !== null &&
    'message' in error &&
    typeof (error as { message: unknown }).message === 'string' &&
    'code' in error
  );
}

/** RAISE EXCEPTION messages this codebase's own migrations use — a `reason: detail` convention, not raw schema. */
const RAISED_MESSAGE_PATTERNS: Array<[RegExp, string]> = [
  [/^insufficient_privilege:/i, "You don't have permission to do this."],
  [/^not_found:/i, 'The requested record could not be found.'],
  [/^email_taken:/i, 'That email address is already registered.'],
  [/^already_accepted:/i, 'This invitation has already been used. Please sign in instead.'],
  [/^invalid_state:/i, 'This invitation is no longer valid.'],
  [/^expired:/i, 'This invitation has expired. Ask your school to send a new one.'],
  [/^inactive_account:/i, 'This account is not active. Contact your school for help.'],
  [/^invalid_role:/i, 'This profile is not a guardian account.'],
  [/^unauthenticated:/i, 'Your session has expired. Please open the invitation link again.'],
];

/** Common Postgres SQLSTATE codes surfaced via constraints, not custom RAISE EXCEPTION text. */
const SQLSTATE_MESSAGES: Record<string, string> = {
  '23505': 'This already exists — please check for a duplicate entry.',
  '23503': "This action can't be completed because it's linked to other records.",
  '23514': 'The information provided is not valid.',
  '23P01': 'This employee already has a shift that overlaps this time.',
  '42501': "You don't have permission to perform this action.",
};

/** Matches `conflict: <detail>` — unlike RAISED_MESSAGE_PATTERNS, the detail after the prefix is shown as-is: these messages (timetable_entries_check_conflicts()) are hand-authored, user-facing sentences naming no table/column/constraint, not raw schema text, so passing them through is exactly what the feature promises ("a clear rejection"), not a leak. */
const CONFLICT_MESSAGE_PATTERN = /^conflict:\s*(.+)$/i;

export function getDbErrorMessage(error: unknown, fallback: string): string {
  if (isPostgrestLikeError(error)) {
    console.error(error);

    const conflictMatch = CONFLICT_MESSAGE_PATTERN.exec(error.message);
    if (conflictMatch?.[1]) return conflictMatch[1];

    for (const [pattern, message] of RAISED_MESSAGE_PATTERNS) {
      if (pattern.test(error.message)) return message;
    }

    const codeMessage = error.code ? SQLSTATE_MESSAGES[error.code] : undefined;
    if (codeMessage) return codeMessage;

    return fallback;
  }

  if (error instanceof Error) return error.message;

  return fallback;
}
