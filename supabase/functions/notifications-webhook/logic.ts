// Pure webhook logic (no I/O): signature verification, replay window, event normalisation. Unit-tested with `deno test`.

export type ReceiptStatus = 'accepted' | 'sent' | 'delayed' | 'delivered' | 'read' | 'failed' | 'bounced' | 'complained';

const encoder = new TextEncoder();

function toBase64(bytes: ArrayBuffer): string {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s);
}

function fromBase64(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Constant-time string comparison (equal-length digests; a length mismatch is simply false). */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmac(hash: 'SHA-1' | 'SHA-256', key: BufferSource, data: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash }, false, ['sign']);
  return toBase64(await crypto.subtle.sign('HMAC', k, encoder.encode(data)));
}

export const TIMESTAMP_TOLERANCE_SECONDS = 300;
export const MAX_BODY_BYTES = 64 * 1024;

/** Replay window: the signed timestamp must be within ±5 minutes of now. */
export function timestampFresh(timestampSeconds: number, nowMs: number = Date.now()): boolean {
  return Number.isFinite(timestampSeconds) && Math.abs(nowMs / 1000 - timestampSeconds) <= TIMESTAMP_TOLERANCE_SECONDS;
}

/**
 * Resend signs webhooks with Svix: HMAC-SHA256 over `${svix-id}.${svix-timestamp}.${rawBody}` with the base64 key that
 * follows the `whsec_` prefix; the header carries one or more space-separated `v1,<base64>` signatures.
 */
export async function verifySvix(
  rawBody: string,
  headers: { id: string | null; timestamp: string | null; signature: string | null },
  secret: string,
  nowMs: number = Date.now(),
): Promise<boolean> {
  if (!secret || !headers.id || !headers.timestamp || !headers.signature) return false;
  if (!timestampFresh(Number(headers.timestamp), nowMs)) return false;
  let key: Uint8Array<ArrayBuffer>;
  try {
    key = fromBase64(secret.startsWith('whsec_') ? secret.slice(6) : secret);
  } catch {
    return false;
  }
  const expected = await hmac('SHA-256', key, `${headers.id}.${headers.timestamp}.${rawBody}`);
  return headers.signature.split(' ').some((part) => {
    const [version, sig] = part.split(',');
    return version === 'v1' && !!sig && safeEqual(sig, expected);
  });
}

/**
 * Twilio: base64(HMAC-SHA1(authToken, url + for each POST param sorted by name: name + value)).
 * `url` must be the exact public URL Twilio was configured to call.
 */
export async function verifyTwilio(
  url: string,
  params: Record<string, string>,
  signature: string | null,
  authToken: string,
): Promise<boolean> {
  if (!authToken || !signature || !url) return false;
  const data = url + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const expected = await hmac('SHA-1', encoder.encode(authToken), data);
  return safeEqual(signature, expected);
}

/** Resend event type → receipt status; unknown/uninteresting types (opened, clicked, …) are ignored. */
export function normaliseResendEvent(type: string): ReceiptStatus | null {
  switch (type) {
    case 'email.sent': return 'sent';
    case 'email.delivered': return 'delivered';
    case 'email.delivery_delayed': return 'delayed';
    case 'email.bounced': return 'bounced';
    case 'email.complained': return 'complained';
    case 'email.failed': return 'failed';
    default: return null;
  }
}

/** Twilio MessageStatus → receipt status. */
export function normaliseTwilioStatus(status: string): ReceiptStatus | null {
  switch (status) {
    case 'queued':
    case 'accepted':
    case 'scheduled':
    case 'sending': return 'accepted';
    case 'sent': return 'sent';
    case 'delivered': return 'delivered';
    case 'read': return 'read';
    case 'undelivered':
    case 'failed': return 'failed';
    default: return null;
  }
}

export interface ParsedReceipt {
  provider: 'resend' | 'twilio';
  eventId: string;
  messageId: string;
  status: ReceiptStatus;
  occurredAt: string;
  detail: string | null;
}

/** Extracts a receipt from a verified Resend payload. Returns null for events we do not track. */
export function parseResend(svixId: string, body: unknown): ParsedReceipt | null {
  if (typeof body !== 'object' || body === null) return null;
  const b = body as { type?: unknown; created_at?: unknown; data?: { email_id?: unknown; bounce?: { message?: unknown } } };
  if (typeof b.type !== 'string') return null;
  const status = normaliseResendEvent(b.type);
  const messageId = b.data?.email_id;
  if (!status || typeof messageId !== 'string' || messageId.length === 0 || messageId.length > 200) return null;
  const when = typeof b.created_at === 'string' && !Number.isNaN(Date.parse(b.created_at)) ? new Date(b.created_at).toISOString() : new Date().toISOString();
  const detail = typeof b.data?.bounce?.message === 'string' ? b.data.bounce.message.slice(0, 200) : null;
  return { provider: 'resend', eventId: svixId, messageId, status, occurredAt: when, detail };
}

/** Extracts a receipt from verified Twilio params. The event id is sid+status so a repeat of the same status is a duplicate. */
export function parseTwilio(params: Record<string, string>): ParsedReceipt | null {
  const sid = params.MessageSid ?? params.SmsSid;
  const raw = params.MessageStatus ?? params.SmsStatus;
  if (!sid || !raw || sid.length > 200) return null;
  const status = normaliseTwilioStatus(raw);
  if (!status) return null;
  const detail = params.ErrorCode ? `twilio_error_${params.ErrorCode}`.slice(0, 200) : null;
  return { provider: 'twilio', eventId: `${sid}:${raw}`, messageId: sid, status, occurredAt: new Date().toISOString(), detail };
}
