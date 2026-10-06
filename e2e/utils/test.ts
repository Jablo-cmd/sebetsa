import { test as base, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { FakeBackend, authSession, type BackendOptions, type Row, type RpcHandler, type Session } from './fakeBackend';
import { FIXED_NOW, ID, PERSONAS, buildDataset, sessionFor, type SignInAs } from './sebetsaFixtures';
import { defaultRpcHandlers } from './rpcHandlers';

/**
 * Sebetsa E2E harness.
 *
 *   import { test, expect } from './utils/test';
 *   test('…', async ({ page, app }) => {
 *     const backend = await app.open('operations_manager');
 *     await page.goto('/leave/management');
 *     …
 *   });
 *
 * Strictness (fails the test, not just logs):
 *   - any request to the Supabase origin the backend did not model;
 *   - any request leaving the app origin (nothing may reach the internet);
 *   - any console error that is not an expected, asserted failure path.
 */

export const APP_ORIGIN = 'http://localhost:5173';
export const SUPABASE_ORIGIN = 'http://localhost:54321';

export interface OpenOptions {
  /** Start signed out (the login page). Default: signed in as `as`. */
  signedIn?: boolean;
  /** Replace/extend fixture tables. */
  tables?: Record<string, Row[]>;
  /** Mutate the freshly built dataset before the backend is created. */
  customize?: (tables: Record<string, Row[]>) => void;
  rpc?: Record<string, RpcHandler>;
  /** MFA factors already enrolled on the signed-in auth user. */
  mfaFactors?: NonNullable<Session['factors']>;
  /** Assurance level of the seeded session (default aal1; aal2 = step-up already completed). */
  aal?: Session['aal'];
  /** Extra known password logins: email → password (session role taken from fixtures). */
  logins?: Record<string, string>;
}

export class AppHarness {
  readonly backends: FakeBackend[] = [];
  readonly offOrigin: string[] = [];

  constructor(private readonly page: Page) {}

  /** Builds the dataset + backend, installs routes, seeds the session and pins the clock. */
  async open(as: SignInAs, options: OpenOptions = {}): Promise<FakeBackend> {
    const tables = buildDataset();
    options.customize?.(tables);
    for (const [name, rows] of Object.entries(options.tables ?? {})) tables[name] = rows;

    const session: Session = { ...sessionFor(as), factors: options.mfaFactors, aal: options.aal };
    const authUsers: BackendOptions['authUsers'] = {};
    for (const persona of Object.values(PERSONAS)) {
      authUsers[persona.email.toLowerCase()] = {
        password: 'Correct-Horse-1!',
        session: { userId: persona.profileId, tenantId: persona.role === 'platform_administrator' ? null : ID.org, role: persona.role === 'employee_two' ? 'employee' : persona.role, email: persona.email },
      };
    }
    for (const [email, password] of Object.entries(options.logins ?? {})) {
      authUsers[email.toLowerCase()] = { password, session };
    }

    const backend = new FakeBackend({
      session,
      tables,
      now: FIXED_NOW,
      authUsers,
      rpc: { ...defaultRpcHandlers, ...(options.rpc ?? {}) },
    });
    this.backends.push(backend);

    await this.page.clock.setFixedTime(new Date(FIXED_NOW));
    await backend.install(this.page, SUPABASE_ORIGIN);

    if (options.signedIn !== false) {
      const stored = JSON.stringify(authSession(session, FIXED_NOW));
      await this.page.addInitScript(([key, value]) => window.localStorage.setItem(key, value), ['sebetsa-auth', stored]);
    }
    return backend;
  }

  /** Seeds a session whose user has no profile row / no tenant, etc., for tenant-gate scenarios. */
  async seedRawSession(user: { id: string; role: string; tenantId: string | null; email: string; emailConfirmed?: boolean; factors?: unknown[] }) {
    const now = FIXED_NOW;
    const stored = JSON.stringify({
      access_token: 'e2e-access-token',
      token_type: 'bearer',
      expires_in: 86400,
      expires_at: Math.floor(new Date(now).getTime() / 1000) + 86400,
      refresh_token: 'e2e-refresh-token',
      user: {
        id: user.id,
        aud: 'authenticated',
        role: 'authenticated',
        email: user.email,
        email_confirmed_at: user.emailConfirmed === false ? null : now,
        phone: '',
        app_metadata: { provider: 'email', providers: ['email'], role: user.role, ...(user.tenantId ? { tenant_id: user.tenantId } : {}) },
        user_metadata: {},
        identities: [],
        factors: user.factors ?? [],
        created_at: now,
        updated_at: now,
      },
    });
    await this.page.addInitScript(([key, value]) => window.localStorage.setItem(key, value), ['sebetsa-auth', stored]);
  }
}

export const test = base.extend<{ app: AppHarness; strictNetwork: void }>({
  app: async ({ page }, use) => {
    await use(new AppHarness(page));
  },
  strictNetwork: [
    async ({ page, app }, use) => {
      // Lowest-priority catch-all (registered first): nothing may leave the app
      // origin, and the Supabase origin is handled only by an installed backend.
      await page.context().route(
        (url) => url.origin !== APP_ORIGIN && url.origin !== SUPABASE_ORIGIN,
        async (route) => {
          app.offOrigin.push(`${route.request().method()} ${route.request().url()}`);
          await route.abort('blockedbyclient');
        },
      );
      await page.context().route(`${SUPABASE_ORIGIN}/**`, async (route) => {
        app.offOrigin.push(`UNMODELLED ${route.request().method()} ${route.request().url()} (no backend installed)`);
        await route.fulfill({ status: 501, contentType: 'application/json', body: JSON.stringify({ message: 'no e2e backend installed', code: 'E2E_UNMOCKED' }) });
      });
      const pageErrors: string[] = [];
      page.on('pageerror', (error) => pageErrors.push(error.message));
      await use();
      expect(pageErrors, 'uncaught exceptions in the page').toEqual([]);
      expect(app.offOrigin, 'requests that left the app origin or hit an uninstalled backend').toEqual([]);
      for (const backend of app.backends) {
        expect(backend.unmocked, 'requests the E2E backend does not model — add them to the fake backend deliberately').toEqual([]);
      }
    },
    { auto: true },
  ],
});

export { expect };

/** axe-core scan: fails on serious/critical violations (WCAG A/AA subset axe can detect). */
export async function expectNoSeriousViolations(page: Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}
