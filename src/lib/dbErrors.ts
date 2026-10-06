/**
 * Translates a thrown Supabase/PostgREST error into copy safe to show end
 * users, instead of the raw table/column/constraint text Postgres returns
 * (e.g. `duplicate key value violates unique constraint "employees_tenant_id_employee_number_key"`).
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

/**
 * RAISE EXCEPTION prefixes Sebetsa's own migrations use — a `reason: detail`
 * convention, not raw schema text. Keep in sync with
 * `grep -oh "raise exception '[a-z_]*:" supabase/migrations/*.sql`.
 */
const RAISED_MESSAGE_PATTERNS: Array<[RegExp, string]> = [
  [/^separation_of_duties:/i, 'You cannot approve, verify or close a record you raised or that concerns you. Ask another authorised person.'],
  [/^insufficient_privilege:/i, "You don't have permission to do this."],
  [/^not_found:/i, 'The requested record could not be found.'],
  [/^cross_tenant_reference:|^cross_reference:/i, 'One of the selected records does not belong to your organisation.'],
  [/^invalid_(leave_|task_)?(status_)?transition:|^invalid_status:/i, 'This record cannot move to that status from its current state. Refresh and try again.'],
  [/^invalid_sequence:/i, 'That action is out of sequence. Refresh and try again.'],
  [/^leave_conflict:/i, 'This conflicts with approved leave for the employee.'],
  [/^insufficient_notice:/i, 'This leave request does not meet the minimum notice period for this leave type.'],
  [/^exceeds_max_consecutive_days:/i, 'This leave request exceeds the maximum consecutive days allowed for this leave type.'],
  [/^documentation_required:/i, 'Supporting documentation is required for this leave type.'],
  [/^invalid_half_day:|^invalid_date_range:|^invalid_period:/i, 'The dates provided are not valid.'],
  [/^insufficient_stock:/i, 'There is not enough stock for this movement.'],
  [/^evidence_required:/i, 'Evidence must be attached before this task can be completed.'],
  [/^checklist_incomplete:/i, 'All checklist items must be completed first.'],
  [/^already_clocked_in:/i, 'You are already clocked in.'],
  [/^already_provisioned:/i, 'This employee already has a login.'],
  [/^missing_email:/i, 'A work email address is required for this employee first.'],
  [/^email_taken:/i, 'That email address is already registered.'],
  [/^invalid_file_type:/i, 'That file type is not allowed.'],
  [/^file_too_large:/i, 'That file is too large.'],
  [/^invalid_configuration:/i, 'This action is not available with the current configuration.'],
  [/^audit_log_immutable:/i, 'Audit history cannot be changed.'],
];

/** Common Postgres SQLSTATE codes surfaced via constraints, not custom RAISE EXCEPTION text. */
const SQLSTATE_MESSAGES: Record<string, string> = {
  '23505': 'This already exists — please check for a duplicate entry.',
  '23503': "This action can't be completed because it's linked to other records.",
  '23514': 'The information provided is not valid.',
  '23P01': 'This employee already has a shift that overlaps this time.',
  '42501': "You don't have permission to perform this action.",
};

/** Matches `conflict: <detail>` — unlike RAISED_MESSAGE_PATTERNS, the detail after the prefix is shown as-is: these messages are hand-authored, user-facing sentences naming no table/column/constraint, not raw schema text, so passing them through is exactly what the feature promises ("a clear rejection"), not a leak. */
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
