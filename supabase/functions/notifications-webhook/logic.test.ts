import { assert, assertEquals } from '@std/assert';
import {
  normaliseResendEvent,
  normaliseTwilioStatus,
  parseResend,
  parseTwilio,
  safeEqual,
  timestampFresh,
  verifySvix,
  verifyTwilio,
} from './logic.ts';

// ---- Published reference vectors (independent of this implementation) ------------------------------------------
// Svix documentation example.
const SVIX_SECRET = 'whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw';
const SVIX_ID = 'msg_p5jXN8AQM9LWM0D4loKWxJek';
const SVIX_TS = '1614265330';
const SVIX_BODY = '{"test": 2432232314}';
const SVIX_SIG = 'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=';
const SVIX_NOW = 1614265330 * 1000 + 1000;

Deno.test('svix: the published example verifies', async () => {
  assert(await verifySvix(SVIX_BODY, { id: SVIX_ID, timestamp: SVIX_TS, signature: SVIX_SIG }, SVIX_SECRET, SVIX_NOW));
});

Deno.test('svix: tampered body, wrong secret, wrong id/timestamp and missing headers are rejected', async () => {
  const h = { id: SVIX_ID, timestamp: SVIX_TS, signature: SVIX_SIG };
  assertEquals(await verifySvix(SVIX_BODY + ' ', h, SVIX_SECRET, SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, h, 'whsec_' + btoa('another-secret-value'), SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, { ...h, id: 'msg_other' }, SVIX_SECRET, SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, { ...h, timestamp: '1614265331' }, SVIX_SECRET, SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, { ...h, signature: null }, SVIX_SECRET, SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, { ...h, id: null }, SVIX_SECRET, SVIX_NOW), false);
  assertEquals(await verifySvix(SVIX_BODY, h, '', SVIX_NOW), false, 'unconfigured secret fails closed');
  assertEquals(await verifySvix(SVIX_BODY, { ...h, signature: 'v2,' + SVIX_SIG.slice(3) }, SVIX_SECRET, SVIX_NOW), false);
});

Deno.test('svix: a valid signature outside the replay window is rejected', async () => {
  const h = { id: SVIX_ID, timestamp: SVIX_TS, signature: SVIX_SIG };
  assertEquals(await verifySvix(SVIX_BODY, h, SVIX_SECRET, SVIX_NOW + 6 * 60_000), false, 'stale (replayed later)');
  assertEquals(await verifySvix(SVIX_BODY, h, SVIX_SECRET, SVIX_NOW - 6 * 60_000), false);
  assert(timestampFresh(1000, 1000 * 1000 + 299_000));
  assertEquals(timestampFresh(1000, 1000 * 1000 + 301_000), false);
  assertEquals(timestampFresh(Number.NaN), false);
});

Deno.test('svix: one of several space-separated signatures may match', async () => {
  const sig = `v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= ${SVIX_SIG}`;
  assert(await verifySvix(SVIX_BODY, { id: SVIX_ID, timestamp: SVIX_TS, signature: sig }, SVIX_SECRET, SVIX_NOW));
});

// Twilio documentation example inputs; the expected signature was computed independently with
// `openssl dgst -sha1 -hmac 12345 -binary | base64` over the documented string (url + sorted name/value pairs).
const TW_TOKEN = '12345';
const TW_URL = 'https://mycompany.com/myapp.php?foo=1&bar=2';
const TW_PARAMS = { CallSid: 'CA1234567890ABCDE', Caller: '+12349013030', Digits: '1234', From: '+12349013030', To: '+18005551212' };
const TW_SIG = '0/KCTR6DLpKmkAf8muzZqo1nDgQ=';

Deno.test('twilio: the published example verifies', async () => {
  assert(await verifyTwilio(TW_URL, TW_PARAMS, TW_SIG, TW_TOKEN));
});

Deno.test('twilio: tampered params, wrong URL, wrong token, missing signature are rejected', async () => {
  assertEquals(await verifyTwilio(TW_URL, { ...TW_PARAMS, Digits: '9999' }, TW_SIG, TW_TOKEN), false);
  assertEquals(await verifyTwilio(TW_URL + '&x=1', TW_PARAMS, TW_SIG, TW_TOKEN), false);
  assertEquals(await verifyTwilio(TW_URL, TW_PARAMS, TW_SIG, 'other'), false);
  assertEquals(await verifyTwilio(TW_URL, TW_PARAMS, null, TW_TOKEN), false);
  assertEquals(await verifyTwilio(TW_URL, TW_PARAMS, TW_SIG, ''), false, 'unconfigured token fails closed');
  assertEquals(await verifyTwilio('', TW_PARAMS, TW_SIG, TW_TOKEN), false, 'unconfigured URL fails closed');
  assertEquals(await verifyTwilio(TW_URL, { ...TW_PARAMS, Extra: 'x' }, TW_SIG, TW_TOKEN), false);
});

Deno.test('safeEqual', () => {
  assert(safeEqual('abc', 'abc'));
  assertEquals(safeEqual('abc', 'abd'), false);
  assertEquals(safeEqual('abc', 'abcd'), false);
});

Deno.test('event normalisation', () => {
  assertEquals(normaliseResendEvent('email.delivered'), 'delivered');
  assertEquals(normaliseResendEvent('email.bounced'), 'bounced');
  assertEquals(normaliseResendEvent('email.complained'), 'complained');
  assertEquals(normaliseResendEvent('email.opened'), null);
  assertEquals(normaliseTwilioStatus('undelivered'), 'failed');
  assertEquals(normaliseTwilioStatus('queued'), 'accepted');
  assertEquals(normaliseTwilioStatus('weird'), null);
});

Deno.test('parsing: resend payloads', () => {
  const ok = parseResend('msg_1', { type: 'email.bounced', created_at: '2026-10-07T10:00:00.000Z', data: { email_id: 're_123', bounce: { message: 'Mailbox full' } } });
  assertEquals(ok, { provider: 'resend', eventId: 'msg_1', messageId: 're_123', status: 'bounced', occurredAt: '2026-10-07T10:00:00.000Z', detail: 'Mailbox full' });
  assertEquals(parseResend('msg_1', { type: 'email.opened', data: { email_id: 're_123' } }), null);
  assertEquals(parseResend('msg_1', { type: 'email.delivered', data: {} }), null, 'missing message id');
  assertEquals(parseResend('msg_1', { type: 'email.delivered', data: { email_id: 'x'.repeat(201) } }), null, 'oversized id');
  assertEquals(parseResend('msg_1', null), null);
  assertEquals(parseResend('msg_1', 'nope'), null);
});

Deno.test('parsing: twilio params; a repeated status has the same event id (duplicate)', () => {
  const a = parseTwilio({ MessageSid: 'SM1', MessageStatus: 'delivered' })!;
  const b = parseTwilio({ MessageSid: 'SM1', MessageStatus: 'delivered' })!;
  assertEquals(a.eventId, 'SM1:delivered');
  assertEquals(a.eventId, b.eventId);
  assertEquals(parseTwilio({ MessageSid: 'SM1', MessageStatus: 'failed', ErrorCode: '30003' })!.detail, 'twilio_error_30003');
  assertEquals(parseTwilio({ MessageStatus: 'delivered' }), null);
  assertEquals(parseTwilio({ MessageSid: 'SM1', MessageStatus: 'mystery' }), null);
});
