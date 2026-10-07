/**
 * Client error reporting.
 *
 * Collects uncaught errors, unhandled promise rejections and React render errors and sends a small,
 * scrubbed report to VITE_ERROR_REPORT_URL (any HTTPS collector: a Sentry-compatible relay, a Supabase Edge
 * Function, a log drain). With no URL configured nothing leaves the browser and errors are only logged, so
 * the integration boundary exists without a vendor being chosen.
 *
 * What is sent: message, stack, route path (no query string, no hash), app version, a timestamp.
 * What is never sent: passwords, tokens, JWTs, API keys, email addresses, phone numbers, form values, cookies,
 * storage contents, request/response bodies. Free text is scrubbed (see `scrub`) before it is stored or sent.
 */

const REDACTED = '[redacted]';

const PATTERNS: [RegExp, string][] = [
  // JWTs (header.payload.signature)
  [/\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*/g, REDACTED],
  // Authorization / Bearer values
  [/\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}/gi, `$1 ${REDACTED}`],
  // key=value or "key":"value" for sensitive keys
  [/(["']?(?:password|passwd|pwd|secret|token|access_token|refresh_token|api[_-]?key|apikey|authorization|code|otp|totp)["']?\s*[:=]\s*)(["']?)[^\s"'&,;}]+\2/gi, `$1${REDACTED}`],
  // Email addresses
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, REDACTED],
  // Long opaque secrets (hex/base64-ish, 32+ chars)
  [/\b[A-Za-z0-9+/_-]{32,}={0,2}/g, REDACTED],
  // Phone-like numbers (9+ digits, optional + and separators)
  [/\+?\d[\d\s().-]{8,}\d/g, REDACTED],
];

export function scrub(text: string, maxLength = 4000): string {
  let out = text;
  for (const [pattern, replacement] of PATTERNS) out = out.replace(pattern, replacement);
  return out.length > maxLength ? `${out.slice(0, maxLength)}…` : out;
}

/** Path only: query strings and hashes can carry tokens (reset links, OAuth callbacks). */
export function safePath(href: string): string {
  try {
    return new URL(href, 'http://localhost').pathname.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, ':id');
  } catch {
    return '/';
  }
}

export interface ErrorReport {
  kind: 'error' | 'unhandledrejection' | 'render';
  message: string;
  stack?: string;
  path: string;
  version: string;
  at: string;
}

const MAX_PER_SESSION = 20;
const DEDUPE_WINDOW_MS = 60_000;
const recent = new Map<string, number>();
let sent = 0;

export function buildReport(kind: ErrorReport['kind'], error: unknown, href = typeof window === 'undefined' ? '/' : window.location.href): ErrorReport {
  const err = error instanceof Error ? error : new Error(typeof error === 'string' ? error : 'Non-error thrown');
  return {
    kind,
    message: scrub(err.message, 500),
    stack: err.stack ? scrub(err.stack) : undefined,
    path: safePath(href),
    version: import.meta.env.VITE_APP_VERSION ?? 'dev',
    at: new Date().toISOString(),
  };
}

export function reportError(kind: ErrorReport['kind'], error: unknown): void {
  const report = buildReport(kind, error);
  const fingerprint = `${report.kind}|${report.message}|${report.path}`;
  const now = Date.now();
  if (now - (recent.get(fingerprint) ?? 0) < DEDUPE_WINDOW_MS || sent >= MAX_PER_SESSION) return;
  recent.set(fingerprint, now);
  sent += 1;

  console.error('[sebetsa:error]', report.kind, report.message);
  const url = import.meta.env.VITE_ERROR_REPORT_URL;
  if (!url) return;
  try {
    // keepalive lets the report survive a page unload; failures are swallowed — reporting must never throw.
    void fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(report),
      keepalive: true,
      credentials: 'omit',
    }).catch(() => undefined);
  } catch {
    // ignore
  }
}

/** Test hook: forget dedupe/rate-limit state. */
export function resetErrorReportingForTests(): void {
  recent.clear();
  sent = 0;
}

export function installGlobalErrorReporting(): void {
  window.addEventListener('error', (event) => reportError('error', event.error ?? event.message));
  window.addEventListener('unhandledrejection', (event) => reportError('unhandledrejection', event.reason));
}
