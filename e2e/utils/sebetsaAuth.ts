import type { Page } from '@playwright/test';

/**
 * Sebetsa auth session mocking for end-to-end tests. The session is written
 * under the app's canonical persistence key, with role and tenant claims
 * matching the authenticated-user mapping used by the application.
 *
 * Sebetsa's persistence key is `sebetsa-auth` (see AUTH_STORAGE_KEY in
 * src/lib/supabase.ts); role and tenant claims live on
 * `app_metadata.role` / `app_metadata.tenant_id` (see toAuthenticatedUser.ts).
 */

export const SEBETSA_USER_ROLES = [
  'platform_administrator',
  'organization_administrator',
  'operations_manager',
  'regional_manager',
  'site_manager',
  'supervisor',
  'hr_user',
  'employee',
  'client_user',
] as const;

export type SebetsaUserRole = (typeof SEBETSA_USER_ROLES)[number];

interface SebetsaSessionOverrides {
  userId?: string;
  tenantId?: string;
  role?: SebetsaUserRole;
  email?: string;
  emailConfirmed?: boolean;
}

export function buildSebetsaUser(overrides: SebetsaSessionOverrides = {}) {
  const {
    userId = '11111111-1111-1111-1111-111111111111',
    tenantId = '22222222-2222-2222-2222-222222222222',
    role = 'employee',
    email = 'test.user@sebetsa.example',
    emailConfirmed = true,
  } = overrides;
  return {
    id: userId,
    aud: 'authenticated',
    role: 'authenticated',
    email,
    email_confirmed_at: emailConfirmed ? '2026-01-01T00:00:00Z' : null,
    phone: '',
    app_metadata: { provider: 'email', providers: ['email'], role, tenant_id: tenantId },
    user_metadata: {},
    identities: [],
    factors: [],
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
}

export function buildSebetsaSession(overrides: SebetsaSessionOverrides = {}) {
  return {
    access_token: 'mock-access-token',
    token_type: 'bearer',
    // Far enough out that auth-js's getSession()/onAuthStateChange never
    // attempts a real network token refresh mid-test.
    expires_in: 86400,
    expires_at: Math.floor(Date.now() / 1000) + 86400,
    refresh_token: 'mock-refresh-token',
    user: buildSebetsaUser(overrides),
  };
}

/** Seeds localStorage with an authenticated Sebetsa session before the app boots — must be called before page.goto(). */
export async function seedSebetsaSession(page: Page, overrides: SebetsaSessionOverrides = {}) {
  const session = buildSebetsaSession(overrides);
  await page.addInitScript(
    ([key, value]) => window.localStorage.setItem(key, value),
    ['sebetsa-auth', JSON.stringify(session)],
  );
}
