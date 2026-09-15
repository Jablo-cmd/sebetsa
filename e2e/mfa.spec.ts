import { test, expect } from '@playwright/test';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildEmployeeRow } from './utils/sebetsaData';

const VERIFIED_TOTP_FACTOR = { id: 'factor-1', factor_type: 'totp' as const, status: 'verified' as const };

test('a qualifying role with no MFA enrolled sees the required banner', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });

  await page.goto('/dashboard');
  await expect(page.getByText('Your role requires two-factor authentication.')).toBeVisible();
  await page.getByRole('link', { name: 'Set up now' }).click();
  await expect(page).toHaveURL(/\/my-profile#mfa-security$/);
});

test('a non-qualifying role never sees the required banner', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/dashboard');
  await expect(page.getByText('Your role requires two-factor authentication.')).toHaveCount(0);
});

test('a qualifying role with a verified factor already on the session does not see the banner', async ({ page }) => {
  // Simulates "already enrolled" without exercising the real enroll/verify
  // network flow (covered live against real Supabase Auth instead) — just
  // seeds the session's own user.factors, exactly what
  // mfaService.listFactors()/getAssuranceLevel() actually read.
  await seedSebetsaSession(page, { role: 'hr_user' });
  await page.addInitScript((factors) => {
    const raw = window.localStorage.getItem('sebetsa-auth');
    if (!raw) return;
    const session = JSON.parse(raw);
    session.user.factors = factors;
    window.localStorage.setItem('sebetsa-auth', JSON.stringify(session));
  }, [VERIFIED_TOTP_FACTOR]);
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });

  await page.goto('/dashboard');
  await expect(page.getByText('Your role requires two-factor authentication.')).toHaveCount(0);
});

test('My Profile shows the Two-Factor Authentication section for every role', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow() });

  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Set up two-factor authentication' })).toBeVisible();
});

test('My Profile shows the Enabled state and a Remove option when a verified factor is already on the session', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await page.addInitScript((factors) => {
    const raw = window.localStorage.getItem('sebetsa-auth');
    if (!raw) return;
    const session = JSON.parse(raw);
    session.user.factors = factors;
    window.localStorage.setItem('sebetsa-auth', JSON.stringify(session));
  }, [VERIFIED_TOTP_FACTOR]);
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }), employee: buildEmployeeRow() });

  await page.goto('/my-profile');
  await expect(page.getByText('Enabled', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Remove two-factor authentication' })).toBeVisible();
});
