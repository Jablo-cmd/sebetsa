import { assert, assertEquals } from '@std/assert';
import { batchLimit, channelConfigured, MAX_ATTEMPTS, type ProviderConfig, retryDelayMs, secretMatches, statusAfterFailure } from './logic.ts';

const none: ProviderConfig = { resendApiKey: '', resendFrom: '', twilioAccountSid: '', twilioAuthToken: '', twilioSmsFrom: '', twilioWhatsappFrom: '' };

Deno.test('the dispatch secret must match exactly; an unset secret never authorises', async () => {
  assert(await secretMatches('correct-horse', 'correct-horse'));
  assert(!(await secretMatches('correct-horsf', 'correct-horse')));
  assert(!(await secretMatches('correct', 'correct-horse')));
  assert(!(await secretMatches('', 'correct-horse')));
  assert(!(await secretMatches(null, 'correct-horse')));
  // A misconfigured (empty) secret must fail closed, even for an empty header.
  assert(!(await secretMatches('', '')));
  assert(!(await secretMatches(null, '')));
});

Deno.test('a channel is attempted only with every credential it needs', () => {
  for (const channel of ['email', 'sms', 'whatsapp'] as const) assert(!channelConfigured(channel, none));
  assert(channelConfigured('email', { ...none, resendApiKey: 'k', resendFrom: 'Sebetsa <no-reply@example.test>' }));
  assert(!channelConfigured('email', { ...none, resendApiKey: 'k' }));
  assert(!channelConfigured('email', { ...none, resendFrom: 'x' }));
  const twilio = { ...none, twilioAccountSid: 'sid', twilioAuthToken: 'tok' };
  assert(!channelConfigured('sms', twilio));
  assert(channelConfigured('sms', { ...twilio, twilioSmsFrom: '+10000000000' }));
  assert(!channelConfigured('whatsapp', { ...twilio, twilioSmsFrom: '+10000000000' }));
  assert(channelConfigured('whatsapp', { ...twilio, twilioWhatsappFrom: '+10000000001' }));
  assert(!channelConfigured('sms', { ...none, twilioSmsFrom: '+10000000000' }));
});

Deno.test('the batch size is bounded and defaults safely', () => {
  assertEquals(batchLimit(undefined), 50);
  assertEquals(batchLimit(null), 50);
  assertEquals(batchLimit({}), 50);
  assertEquals(batchLimit({ limit: 'many' }), 50);
  assertEquals(batchLimit({ limit: -5 }), 50);
  assertEquals(batchLimit({ limit: 0 }), 50);
  assertEquals(batchLimit({ limit: Number.NaN }), 50);
  assertEquals(batchLimit({ limit: 10 }), 10);
  assertEquals(batchLimit({ limit: 10_000 }), 200);
  assertEquals(batchLimit({ limit: 0.4 }), 1);
});

Deno.test('retries back off exponentially, capped at one hour, and dead-letter after the last attempt', () => {
  assertEquals(retryDelayMs(1), 2 * 60_000);
  assertEquals(retryDelayMs(2), 4 * 60_000);
  assertEquals(retryDelayMs(5), 32 * 60_000);
  assertEquals(retryDelayMs(20), 60 * 60_000);
  for (let attempts = 1; attempts < MAX_ATTEMPTS; attempts++) assertEquals(statusAfterFailure(attempts), 'pending');
  assertEquals(statusAfterFailure(MAX_ATTEMPTS), 'dead_letter');
  assertEquals(statusAfterFailure(MAX_ATTEMPTS + 3), 'dead_letter');
});
