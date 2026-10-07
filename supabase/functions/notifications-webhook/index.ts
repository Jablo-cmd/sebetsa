// Sebetsa provider delivery-receipt webhook.
//   POST ?provider=resend   Svix-signed JSON (svix-id, svix-timestamp, svix-signature)
//   POST ?provider=twilio   form-encoded, X-Twilio-Signature
// Order of checks: method -> size -> signature (and replay window for Resend) -> parse -> record. Nothing is parsed or
// recorded before the signature is verified, and an unconfigured provider rejects everything (fail closed).
// Receipts are idempotent in the database (unique provider event id); a replayed request returns 200 and changes nothing.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  MAX_BODY_BYTES,
  type ParsedReceipt,
  parseResend,
  parseTwilio,
  verifySvix,
  verifyTwilio,
} from './logic.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const resendWebhookSecret = Deno.env.get('RESEND_WEBHOOK_SECRET') ?? '';
const twilioAuthToken = Deno.env.get('TWILIO_AUTH_TOKEN') ?? '';
// The exact public URL Twilio calls, including the query string (Twilio signs it).
const twilioWebhookUrl = Deno.env.get('TWILIO_WEBHOOK_URL') ?? '';

function log(event: string, fields: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), fn: 'notifications-webhook', event, ...fields }));
}

function respond(status: number, body: Record<string, unknown> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return respond(405, { error: 'method_not_allowed' });
  const provider = new URL(req.url).searchParams.get('provider');
  if (provider !== 'resend' && provider !== 'twilio') return respond(400, { error: 'unknown_provider' });

  const declared = Number(req.headers.get('content-length') ?? 0);
  if (declared > MAX_BODY_BYTES) return respond(413, { error: 'too_large' });
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return respond(413, { error: 'too_large' });

  let receipt: ParsedReceipt | null = null;
  try {
    if (provider === 'resend') {
      const ok = await verifySvix(
        raw,
        { id: req.headers.get('svix-id'), timestamp: req.headers.get('svix-timestamp'), signature: req.headers.get('svix-signature') },
        resendWebhookSecret,
      );
      if (!ok) {
        log('rejected', { provider, reason: resendWebhookSecret ? 'bad_signature_or_stale' : 'not_configured' });
        return respond(401, { error: 'unauthorized' });
      }
      receipt = parseResend(req.headers.get('svix-id')!, JSON.parse(raw));
    } else {
      const params = Object.fromEntries(new URLSearchParams(raw));
      const ok = await verifyTwilio(twilioWebhookUrl, params, req.headers.get('x-twilio-signature'), twilioAuthToken);
      if (!ok) {
        log('rejected', { provider, reason: twilioAuthToken && twilioWebhookUrl ? 'bad_signature' : 'not_configured' });
        return respond(401, { error: 'unauthorized' });
      }
      receipt = parseTwilio(params);
    }
  } catch {
    log('rejected', { provider, reason: 'malformed' });
    return respond(400, { error: 'malformed' });
  }

  // A verified event we do not track (opened, clicked, ...) is acknowledged so the provider stops retrying.
  if (!receipt) return respond(200, { result: 'ignored' });

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const { data, error } = await supabase.rpc('record_delivery_receipt', {
    p_provider: receipt.provider,
    p_event_id: receipt.eventId,
    p_message_id: receipt.messageId,
    p_event_type: receipt.status,
    p_occurred_at: receipt.occurredAt,
    p_detail: receipt.detail,
  });
  if (error) {
    // 500 makes the provider retry; the receipt is idempotent so a retry is safe.
    log('record_failed', { provider, code: error.code });
    return respond(500, { error: 'record_failed' });
  }
  log('receipt', { provider, status: receipt.status, result: data });
  return respond(200, { result: data });
});
