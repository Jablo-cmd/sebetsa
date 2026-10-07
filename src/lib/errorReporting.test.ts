import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildReport, reportError, resetErrorReportingForTests, safePath, scrub } from './errorReporting';

// Built at runtime so no key-shaped literal sits in the repository (secret scanners cannot tell a fixture from a leak).
const opaqueKey = ['k', 'live', '4eC39HqLyjWDarjtT1zdp7dc'].join('_') + 'ABCDEFGH';

describe('scrub', () => {
  it('removes JWTs, bearer tokens, key=value secrets, emails and long opaque strings', () => {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.c2lnbmF0dXJlLXNpZ25hdHVyZQ';
    const text = [
      `token ${jwt}`,
      'Authorization: Bearer abcDEF1234567890xyz',
      'password=hunter2 and {"access_token":"abc123def456"}',
      'contact thabo.m@example.co.za',
      `key ${opaqueKey}`,
      'phone +27 82 123 4567',
    ].join(' | ');
    const out = scrub(text);
    for (const secret of [jwt, 'abcDEF1234567890xyz', 'hunter2', 'abc123def456', 'thabo.m@example.co.za', opaqueKey, '82 123 4567']) {
      expect(out).not.toContain(secret);
    }
    expect(out).toContain('[redacted]');
  });

  it('keeps ordinary diagnostic text and truncates long input', () => {
    expect(scrub('Cannot read properties of undefined (reading "map")')).toContain('Cannot read properties of undefined');
    expect(scrub('x'.repeat(10_000), 100).length).toBeLessThanOrEqual(101);
  });
});

describe('safePath', () => {
  it('drops query string and hash and masks ids', () => {
    expect(safePath('https://app.example/reset-password?token=abc#access_token=xyz')).toBe('/reset-password');
    expect(safePath('https://app.example/users/0b2f6c1e-1a2b-4c3d-8e9f-0123456789ab')).toBe('/users/:id');
  });
});

describe('reportError', () => {
  beforeEach(() => {
    resetErrorReportingForTests();
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('sends nothing when no endpoint is configured', () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    reportError('error', new Error('boom'));
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('posts a scrubbed report, deduplicates, and never throws', async () => {
    vi.stubEnv('VITE_ERROR_REPORT_URL', 'https://collector.example/report');
    const fetchSpy = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchSpy);
    reportError('error', new Error('failed for a@b.co with password=hunter2'));
    reportError('error', new Error('failed for a@b.co with password=hunter2'));
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const init = fetchSpy.mock.calls[0]![1] as { credentials?: string; body?: unknown };
    expect(init.credentials).toBe('omit');
    const body = String(init.body);
    expect(body).not.toContain('hunter2');
    expect(body).not.toContain('a@b.co');

    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('network')));
    expect(() => reportError('error', new Error('different'))).not.toThrow();
  });

  it('builds a report with only message, stack, path, version and time', () => {
    const report = buildReport('render', new Error('x'), 'https://app.example/a?b=c');
    expect(Object.keys(report).sort()).toEqual(['at', 'kind', 'message', 'path', 'stack', 'version']);
    expect(report.path).toBe('/a');
  });
});
