# Sebetsa notification delivery

Sebetsa supports in-app notifications through the `notifications` records,
header notification bell, and notifications inbox. This document describes
optional external delivery by email, SMS, or WhatsApp. External messages are
not sent unless the dispatch function is deployed and configured with valid
provider credentials.

## Components

| Component | Responsibility |
| --- | --- |
| `notification_preferences` | Per-user channel preferences and optional per-type overrides. |
| `notification_deliveries` | Outbox records for opted-in external channels. New records begin as `pending`; records without usable contact details may be skipped. |
| `resolve_notification_channels(profile, organization, type)` | Resolves delivery channels using organization-level configuration and user preferences. |
| `notification_delivery_schedule(profile)` | Returns the delivery time, respecting configured quiet hours. |
| `enqueue_notification_deliveries(notification_id)` | Queues external deliveries when a notification is created. |
| `supabase/functions/notifications-dispatch` | Worker that processes pending deliveries through provider adapters. |

## Delivery lifecycle

The worker selects pending rows whose scheduled time has arrived and which
have fewer than five attempts. Successful deliveries are marked `sent` and
store the provider message ID. Retryable failures return to `pending` with
an incremented attempt count; exhausted deliveries are marked `failed`.

## Dispatch function

- **Authentication:** send `POST` with `x-dispatch-secret`. If
  `NOTIFICATIONS_DISPATCH_SECRET` is unset, the function fails closed.
- **Optional body:** `{ "limit": 50 }`, with a supported limit from 1 to 200.
- **Email:** Resend, configured with `RESEND_API_KEY` and `RESEND_FROM`.
- **SMS:** Twilio, configured with `TWILIO_ACCOUNT_SID`,
  `TWILIO_AUTH_TOKEN`, and `TWILIO_SMS_FROM`.
- **WhatsApp:** Twilio, configured with `TWILIO_ACCOUNT_SID`,
  `TWILIO_AUTH_TOKEN`, and `TWILIO_WHATSAPP_FROM`.

When provider credentials are missing, the affected pending rows are left
untouched and reported as unconfigured. In-app notifications continue to
work independently.

## Enabling external delivery

1. Deploy with `supabase functions deploy notifications-dispatch`.
2. Set only the provider secrets you intend to use with
   `supabase secrets set NAME=value`.
3. Configure a trusted scheduler to call the dispatch endpoint.
4. Verify delivery and failure handling before enabling the channel for users.

Do not place provider secrets in `VITE_*` variables, browser code, or source
control. Keep organization-level configuration free of secret keys and
credentials.
