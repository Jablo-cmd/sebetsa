# Notification delivery (in-app, email, SMS, WhatsApp)

Every notification is delivered **in-app** (a `notifications` row, the header
bell, the `/notifications` inbox). A user can additionally opt into **email**,
**SMS** and **WhatsApp**. This document describes how external delivery works
and — just as importantly — what it does *not* do until it is configured.

> **Nothing is sent externally until all three of these are true:** the Edge
> Function is deployed, something calls it on a schedule, and the provider
> secrets for that channel are set. Until then in-app notifications are
> unaffected and external deliveries wait as `pending`. The application never
> reports an external message as sent when it was not.

## The pieces

| Piece | Role |
| ----- | ---- |
| `notifications` | The in-app notification. Rows are created only by `create_notification()` (SECURITY DEFINER, not executable by `authenticated`), always from inside a privileged RPC. |
| `notification_preferences` | Per-user opt-in per external channel (`email_enabled`, `sms_enabled`, `whatsapp_enabled`) and optional quiet hours. Default is **off**. A user can read and change only their own row. Managed at `/notifications/settings`. |
| `enqueue_notification_deliveries()` | `AFTER INSERT` trigger on `notifications`. Adds one `notification_deliveries` row per channel the recipient opted into. See rules below. |
| `notification_deliveries` | The outbox. One row per (notification, channel), unique. Statuses: `pending → claimed → processing → sent`, or back to `pending` with a retry delay, or `dead_letter` after 5 attempts (`failed` is reserved). Users can read only their own rows; nobody writes to it from the browser. |
| `claim_notification_deliveries()` | Atomic claim with a lease (`FOR UPDATE SKIP LOCKED`), executable by `service_role` only. A crashed worker's lease expires and the rows are claimed again. |
| `supabase/functions/notifications-dispatch` | The worker. Claims a batch, calls the provider adapter for each row, records the result. |

### What the enqueue trigger does

- Only an **active** profile receives external messages.
- A channel needs a destination: email uses `profiles.email`; SMS and WhatsApp use `profiles.phone`. If it is missing, nothing is queued for that channel.
- **Quiet hours** defer a delivery to the end of the window. The times are stored without a time zone, so they are currently evaluated in **UTC**. A per-user time zone is a known gap — see the roadmap.
- It is idempotent (`unique (notification_id, channel)`), and in-app notifications are never blocked by it.
- Covered by `supabase/rls-tests/tests/notification_enqueue.test.sql`.

## The worker: `notifications-dispatch`

- **Authentication:** `POST` with header `x-dispatch-secret: <NOTIFICATIONS_DISPATCH_SECRET>`, compared in constant time (hash first, so length does not leak). If the secret is not configured the function rejects **every** request (fail closed). Failures are logged as `unauthorized` without the supplied value.
- **Body (optional):** `{ "limit": 1..200 }`, default 50.
- **Adapters**
  - `email` → Resend: `RESEND_API_KEY`, `RESEND_FROM` (a sender you have verified; there is no default sender).
  - `sms` → Twilio: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_SMS_FROM`.
  - `whatsapp` → Twilio: the same account plus `TWILIO_WHATSAPP_FROM`.
- A channel whose secrets are missing is not attempted: its rows are released back to `pending` and rescheduled 15 minutes out, and `skippedUnconfigured` is reported.
- **Retries:** exponential backoff starting at 2 minutes, capped at one hour; after 5 attempts the row is `dead_letter` with the last error. Provider message ids are unique, so a replay cannot record the same message twice.
- **Logging:** one structured JSON line per event (`unauthorized`, `claim_failed`, `batch_complete`) with counts only — no destinations, bodies or secrets.
- **Response:** `{ ok, scanned, sent, failed, skippedUnconfigured }`.
- **Concurrency is tested for real:** `supabase/rls-tests/concurrency.sh` runs two simultaneous sessions claiming from 40 committed deliveries and asserts the claims are disjoint, complete and fenced (a worker that does not hold the lease cannot finish the row). It runs as part of the RLS gate in CI.
- Pure logic (secret comparison, channel configuration, batch limits, retry schedule) lives in `logic.ts` and is unit-tested with `deno test` in CI.

## Production activation

1. `supabase functions deploy notifications-dispatch`
2. `supabase secrets set NOTIFICATIONS_DISPATCH_SECRET=… ` plus the provider secrets for the channels you use (see `.env.example`).
3. Schedule it: `pg_cron` + `pg_net` (`select net.http_post(...)` every minute with the secret header) or any external scheduler.
4. Ask users to enable channels at `/notifications/settings` (and make sure their profile has an email / phone number).

Steps 1–3 are **not verified in this repository** — they require the live Supabase project. See the readiness scorecard.

## Webhooks

No inbound webhook endpoint exists in this repository (the only Edge Function is the dispatcher, which is called with a shared secret). There is therefore nothing to authenticate, replay-protect or deduplicate yet, and no adversarial webhook tests exist. When provider delivery receipts are built they must verify the provider signature and timestamp, reject replays, be idempotent on the provider event id, and ship with those adversarial tests.

## Not built yet

- Provider delivery receipts / bounce webhooks (would need an authenticated, replay-safe, idempotent endpoint — see `SECURITY.md`).
- A delivery-status dashboard and alerting on `dead_letter` growth.
- Per-user time zone for quiet hours.
- Tenant-level channel kill-switch and non-secret sender configuration.
