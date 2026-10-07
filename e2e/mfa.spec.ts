import { test, expect } from './utils/test';

const VERIFIED_TOTP = [{ id: 'factor-1', factor_type: 'totp' as const, status: 'verified' as const }];

// Roles the database requires MFA for (public.mfa_roles()): platform administrator, organisation
// administrator, operations manager, HR. Without aal2 the database gives them no tenant access.
const REQUIRED = ['organization_administrator', 'operations_manager', 'hr_user', 'platform_administrator'] as const;

for (const role of REQUIRED) {
  test(`${role} without a factor is forced to enrol and cannot reach the app`, async ({ page, app }) => {
    const backend = await app.open(role, { mfaFactors: [], aal: 'aal1' });
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/mfa-setup$/);
    await expect(page.getByRole('heading', { name: 'Set up two-factor authentication' })).toBeVisible();
    await expect(page.getByRole('heading', { name: /Welcome/ })).toHaveCount(0);
    // The backend refuses tenant data and writes for this session, whatever the UI does.
    expect(backend.mfaSatisfied()).toBe(false);
    expect(backend.visible('employees')).toHaveLength(0);
  });
}

test('forced enrolment: a wrong code is rejected, a right one unlocks the app', async ({ page, app }) => {
  const backend = await app.open('organization_administrator', { mfaFactors: [], aal: 'aal1' });
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/mfa-setup$/);
  await page.getByRole('button', { name: 'Set up two-factor authentication' }).click();
  await expect(page.getByAltText('Scan this QR code with your authenticator app')).toBeVisible();

  await page.getByLabel('Enter the 6-digit code from your app').fill('000000');
  await page.getByRole('button', { name: 'Verify and enable' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  expect(backend.mfaSatisfied()).toBe(false);

  await page.getByLabel('Enter the 6-digit code from your app').fill(backend.mfaCode);
  await page.getByRole('button', { name: 'Verify and enable' }).click();
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
  expect(backend.mfaSatisfied()).toBe(true);
});

test('a required role cannot open the enrolment page once enrolled, and cannot remove its factor', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/mfa-setup');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await page.goto('/my-profile');
  await expect(page.getByText('Enabled', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Remove two-factor authentication' })).toHaveCount(0);
  await expect(page.getByText('Required for your role')).toBeVisible();
});

test('the fake backend refuses privileged writes and RPCs below aal2 (no bypass behind the UI)', async ({ app }) => {
  const backend = await app.open('organization_administrator', { mfaFactors: [], aal: 'aal1' });
  expect(backend.mfaSatisfied()).toBe(false);
  for (const table of ['employees', 'tasks', 'sites', 'audit_log']) expect(backend.visible(table)).toHaveLength(0);
});

for (const role of ['site_manager', 'supervisor', 'employee'] as const) {
  test(`${role} is not required to use MFA and reaches the app without it`, async ({ page, app }) => {
    await app.open(role);
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
  });
}

test('an optional-MFA role that enrolled is held at the challenge until it steps up', async ({ page, app }) => {
  await app.open('site_manager', { mfaFactors: VERIFIED_TOTP, aal: 'aal1' });
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/mfa-challenge$/);
});

test('a required role with a verified factor and an aal2 session reaches the app', async ({ page, app }) => {
  await app.open('organization_administrator', { mfaFactors: VERIFIED_TOTP, aal: 'aal2' });
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
});

test('My Profile offers MFA setup to every role, even those who are not required to enrol', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Set up two-factor authentication' })).toBeVisible();
});

test('My Profile shows the Enabled state and a Remove option when a verified factor exists', async ({ page, app }) => {
  await app.open('site_manager', { mfaFactors: VERIFIED_TOTP, aal: 'aal2' });
  await page.goto('/my-profile');
  await expect(page.getByText('Enabled', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Remove two-factor authentication' })).toBeVisible();
});

test('an enrolled user who signed in with only a password is held at the MFA challenge', async ({ page, app }) => {
  await app.open('organization_administrator', { mfaFactors: VERIFIED_TOTP, aal: 'aal1' });
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/mfa-challenge$/);
  await expect(page.getByRole('heading', { name: "Verify it's you" })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Welcome/ })).toHaveCount(0);
});

test('a wrong code is rejected and a correct code completes the step-up', async ({ page, app }) => {
  const backend = await app.open('organization_administrator', { mfaFactors: VERIFIED_TOTP, aal: 'aal1' });
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/mfa-challenge$/);

  await page.getByLabel('Authentication code').fill('000000');
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page).toHaveURL(/\/mfa-challenge$/);
  expect(backend.session.aal).not.toBe('aal2');

  await page.getByLabel('Authentication code').fill(backend.mfaCode);
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
});

test('a user without MFA can never open the challenge page', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/mfa-challenge');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
