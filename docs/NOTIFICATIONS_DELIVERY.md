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
- **Quiet hours** defer a delivery to the end of the window, evaluated in the recipient's own IANA time zone (`notification_preferences.time_zone`, chosen at `/notifications/settings`), else the organisation's `timezone`, else UTC — never an assumed country. Windows that cross midnight and daylight-saving changes are handled in local wall-clock time (`quiet_hours_release()`); an unknown zone is rejected on save and ignored by the evaluator. Covered by `quiet_hours_time_zone.test.sql` (multi-zone, half-hour offsets, spring-forward/fall-back, nonexistent local time).
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

## Delivery receipts (provider webhooks)

**Status: IMPLEMENTED and tested locally — NOT LIVE VERIFIED.** No real provider has called it; the signature code is verified against reference vectors, not against live Resend or Twilio traffic.

`supabase/functions/notifications-webhook` (`verify_jwt = false`; authentication is the provider signature):

- `POST ?provider=resend`: Svix signature (`svix-id`, `svix-timestamp`, `svix-signature`, HMAC-SHA256 with `RESEND_WEBHOOK_SECRET`), **replay window ±5 minutes**. Tracked events: sent, delivered, delivery_delayed, bounced, complained, failed.
- `POST ?provider=twilio`: `X-Twilio-Signature` (HMAC-SHA1 over the exact public URL `TWILIO_WEBHOOK_URL` plus sorted parameters, keyed with `TWILIO_AUTH_TOKEN`). Statuses: accepted/queued/sending, sent, delivered, read, undelivered/failed.
- Order of checks: method → size (64 KB) → signature → parse → record. Nothing is parsed or stored before the signature verifies; a provider without its secret configured rejects every call (fail closed); rejected calls log the reason only, never the payload.
- **Idempotent:** `unique (provider, provider_event_id)`. Resend's event id is `svix-id`; Twilio's is `MessageSid:MessageStatus`. A replayed request returns 200 and changes nothing.
- **Monotonic:** a later-arriving older status never regresses a delivery (`receipt_rank`).
- **Message ids:** `record_delivery_receipt()` matches on the provider message id the dispatcher stored, and only within the provider's own channels (a Resend id cannot update an SMS delivery).
- **Early receipts:** a receipt that arrives before the dispatcher has stored the message id is kept unmatched and applied by the scheduled job `reconcile_receipts` (every 10 minutes).
- **Outbox untouched:** receipts write only `provider*`, `delivered_at`, `provider_error` and the event log — never `status`, lease, `worker_id`, `attempts` or `scheduled_for`, so claim / lease / `SKIP LOCKED` / fencing behave exactly as before (asserted in `delivery_receipts.test.sql`).
- **Visibility:** `ops_health()` reports receipt failures (24 h), sent-without-receipt and unmatched receipts; alerts `notifications_receipt_failures` and `notifications_unmatched_receipts` (see OPERATIONS.md). Users still read only their own delivery rows.
- **Retry monitoring:** outbox retries/dead letters are covered by the existing alerts (`notifications_backlog`, `notifications_dead_letter`, `notifications_leases_expiring`).

Activation (not done here): deploy `notifications-webhook`; `supabase secrets set RESEND_WEBHOOK_SECRET=… TWILIO_WEBHOOK_URL=…` (Twilio reuses `TWILIO_AUTH_TOKEN`); register `https://<ref>.supabase.co/functions/v1/notifications-webhook?provider=resend` in Resend and `…?provider=twilio` as the Twilio status callback; enable pg_cron so `reconcile_receipts` runs.

Tests: `supabase/functions/notifications-webhook/logic.test.ts` (reference vectors, tampered body, wrong secret/id/timestamp, missing headers, unconfigured secret, stale and future timestamps, multiple signatures, oversized ids, duplicate event ids) and `supabase/rls-tests/tests/delivery_receipts.test.sql` (idempotency, ordering, cross-channel isolation, reconciliation, untouched outbox state, service-role-only).

## Not built yet

- A delivery-status dashboard for tenant administrators (alerting on dead letters and receipt failures exists; see OPERATIONS.md).
- Tenant-level channel kill-switch and non-secret sender configuration.
