// Pure, dependency-free helpers for the notification dispatcher, kept apart
// from index.ts (which reads the environment and starts the server on import)
// so they can be unit-tested with `deno test`.

export type Channel = 'email' | 'sms' | 'whatsapp';

export const MAX_ATTEMPTS = 5;
export const DEFAULT_BATCH = 50;
export const MAX_BATCH = 200;

/** Constant-time comparison of the dispatch secret (hash first so length does not leak). */
export async function secretMatches(provided: string | null, expected: string): Promise<boolean> {
  if (expected.length === 0 || provided === null) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(provided)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

export interface ProviderConfig {
  resendApiKey: string;
  resendFrom: string;
  twilioAccountSid: string;
  twilioAuthToken: string;
  twilioSmsFrom: string;
  twilioWhatsappFrom: string;
}

/** A channel is only attempted when every credential it needs is present. */
export function channelConfigured(channel: Channel, c: ProviderConfig): boolean {
  if (channel === 'email') return c.resendApiKey.length > 0 && c.resendFrom.length > 0;
  const twilio = c.twilioAccountSid.length > 0 && c.twilioAuthToken.length > 0;
  if (channel === 'sms') return twilio && c.twilioSmsFrom.length > 0;
  return twilio && c.twilioWhatsappFrom.length > 0;
}

/** Batch size from an optional request body: positive numbers only, capped. */
export function batchLimit(body: unknown): number {
  const limit = (body as { limit?: unknown } | null)?.limit;
  if (typeof limit === 'number' && Number.isFinite(limit) && limit > 0) return Math.min(Math.floor(limit) || 1, MAX_BATCH);
  return DEFAULT_BATCH;
}

/** Exponential backoff from 2 minutes, capped at one hour. */
export function retryDelayMs(nextAttempts: number): number {
  return Math.min(60 * 60_000, 2 ** nextAttempts * 60_000);
}

/** A failed delivery is retried until it has been attempted MAX_ATTEMPTS times, then dead-lettered. */
export function statusAfterFailure(nextAttempts: number): 'pending' | 'dead_letter' {
  return nextAttempts >= MAX_ATTEMPTS ? 'dead_letter' : 'pending';
}
