// Sebetsa notification dispatcher — drains the notification_deliveries outbox.
// Delivery rows are atomically claimed by a service-role worker with a lease.
// Provider secrets remain server-side; missing provider configuration does not
// send or fabricate a product identity.
// Invocation: POST with x-dispatch-secret. Body (optional): { limit?: number }.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const dispatchSecret = Deno.env.get('NOTIFICATIONS_DISPATCH_SECRET') ?? '';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const RESEND_FROM = Deno.env.get('RESEND_FROM') ?? '';
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID') ?? '';
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN') ?? '';
const TWILIO_SMS_FROM = Deno.env.get('TWILIO_SMS_FROM') ?? '';
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM') ?? '';

const MAX_ATTEMPTS = 5;

interface DeliveryRow {
  id: string;
  notification_id: string;
  recipient_profile_id: string;
  channel: 'email' | 'sms' | 'whatsapp';
  destination: string | null;
  attempts: number;
}

interface NotificationRow {
  title: string;
  body: string;
  link_path: string | null;
}

type AdapterResult = { ok: true; providerMessageId: string | null } | { ok: false; error: string };

function channelConfigured(channel: DeliveryRow['channel']): boolean {
  if (channel === 'email') return RESEND_API_KEY.length > 0 && RESEND_FROM.length > 0;
  if (channel === 'sms') return TWILIO_ACCOUNT_SID.length > 0 && TWILIO_AUTH_TOKEN.length > 0 && TWILIO_SMS_FROM.length > 0;
  return TWILIO_ACCOUNT_SID.length > 0 && TWILIO_AUTH_TOKEN.length > 0 && TWILIO_WHATSAPP_FROM.length > 0;
}

async function sendEmail(to: string, subject: string, text: string): Promise<AdapterResult> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: RESEND_FROM, to, subject, text }),
  });
  if (!res.ok) return { ok: false, error: `resend_${res.status}: ${(await res.text()).slice(0, 200)}` };
  const payload = (await res.json()) as { id?: string };
  return { ok: true, providerMessageId: payload.id ?? null };
}

async function sendTwilio(from: string, to: string, body: string): Promise<AdapterResult> {
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;
  const form = new URLSearchParams({ From: from, To: to, Body: body });
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: form.toString(),
  });
  if (!res.ok) return { ok: false, error: `twilio_${res.status}: ${(await res.text()).slice(0, 200)}` };
  const payload = (await res.json()) as { sid?: string };
  return { ok: true, providerMessageId: payload.sid ?? null };
}

function deliver(row: DeliveryRow, notification: NotificationRow): Promise<AdapterResult> {
  const to = (row.destination ?? '').trim();
  if (to.length === 0) return { ok: false, error: 'no_destination' };
  const text = `${notification.body}${notification.link_path ? `\n\n${notification.link_path}` : ''}`;

  if (row.channel === 'email') return sendEmail(to, notification.title, text);
  if (row.channel === 'sms') return sendTwilio(TWILIO_SMS_FROM, to, `${notification.title}\n${text}`);
  return sendTwilio(`whatsapp:${TWILIO_WHATSAPP_FROM}`, `whatsapp:${to}`, `${notification.title}\n${text}`);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (dispatchSecret.length === 0 || req.headers.get('x-dispatch-secret') !== dispatchSecret) {
    return json({ error: 'unauthorized' }, 401);
  }

  let limit = 50;
  try {
    const body = (await req.json()) as { limit?: number };
    if (typeof body.limit === 'number' && body.limit > 0) limit = Math.min(body.limit, 200);
  } catch {
    /* empty body is fine */
  }

  const s = createClient(supabaseUrl, serviceKey);

  const workerId = `notifications-${crypto.randomUUID()}`;
  const { data: pending, error } = await s.rpc('claim_notification_deliveries', {
    p_limit: limit,
    p_worker_id: workerId,
    p_lease_seconds: 300,
  });
  if (error) return json({ error: error.message }, 500);

  const rows = (pending ?? []) as DeliveryRow[];
  const result = { scanned: rows.length, sent: 0, failed: 0, skippedUnconfigured: 0 };

  for (const row of rows) {
    if (!channelConfigured(row.channel)) {
      await s.from('notification_deliveries').update({ status: 'pending', scheduled_for: new Date(Date.now() + 15 * 60_000).toISOString(), claimed_at: null, claim_expires_at: null, worker_id: null }).eq('id', row.id).eq('worker_id', workerId);
      result.skippedUnconfigured += 1;
      continue;
    }

    const { data: notification } = await s
      .from('notifications')
      .select('title, body, link_path')
      .eq('id', row.notification_id)
      .maybeSingle();
    if (!notification) {
      await s.from('notification_deliveries').update({ status: 'dead_letter', error: 'notification_missing', worker_id: null, claimed_at: null, claim_expires_at: null }).eq('id', row.id).eq('worker_id', workerId);
      result.failed += 1;
      continue;
    }

    await s.from('notification_deliveries').update({ status: 'processing', updated_at: new Date().toISOString() }).eq('id', row.id).eq('worker_id', workerId).eq('status', 'claimed');

    let outcome: AdapterResult;
    try {
      outcome = await deliver(row, notification as NotificationRow);
    } catch (err) {
      outcome = { ok: false, error: `exception: ${String(err).slice(0, 200)}` };
    }

    if (outcome.ok) {
      await s
        .from('notification_deliveries')
        .update({
          status: 'sent',
          worker_id: null,
          claimed_at: null,
          claim_expires_at: null,
          sent_at: new Date().toISOString(),
          attempts: row.attempts + 1,
          provider_message_id: outcome.providerMessageId,
          error: null,
        })
        .eq('id', row.id).eq('worker_id', workerId);
      result.sent += 1;
    } else {
      const nextAttempts = row.attempts + 1;
      await s
        .from('notification_deliveries')
        .update({
          status: nextAttempts >= MAX_ATTEMPTS ? 'dead_letter' : 'pending',
          scheduled_for: new Date(Date.now() + Math.min(60 * 60_000, 2 ** nextAttempts * 60_000)).toISOString(),
          worker_id: null,
          claimed_at: null,
          claim_expires_at: null,
          attempts: nextAttempts,
          error: outcome.error,
        })
        .eq('id', row.id).eq('worker_id', workerId);
      result.failed += 1;
    }
  }

  return json({ ok: true, ...result });
});
