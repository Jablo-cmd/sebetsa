import { test, expect } from './utils/test';

const VERIFIED_TOTP = [{ id: 'factor-1', factor_type: 'totp' as const, status: 'verified' as const }];

// Roles that must use MFA: platform_administrator, organization_administrator, hr_user.

test('a role that requires MFA and has none enrolled sees the banner and is taken to the setup section', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/dashboard');
  await expect(page.getByText('Your role requires two-factor authentication.')).toBeVisible();
  await page.getByRole('link', { name: 'Set up now' }).click();
  await expect(page).toHaveURL(/\/my-profile#mfa-security$/);
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
});

test('hr_user (handles personal data) is also required to enrol', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto('/dashboard');
  await expect(page.getByText('Your role requires two-factor authentication.')).toBeVisible();
});

for (const role of ['operations_manager', 'site_manager', 'supervisor', 'employee'] as const) {
  test(`${role} never sees the required-MFA banner`, async ({ page, app }) => {
    await app.open(role);
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
    await expect(page.getByText('Your role requires two-factor authentication.')).toHaveCount(0);
  });
}

test('a required role with a verified factor already enrolled does not see the banner', async ({ page, app }) => {
  await app.open('organization_administrator', { mfaFactors: VERIFIED_TOTP, aal: 'aal2' });
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
  await expect(page.getByText('Your role requires two-factor authentication.')).toHaveCount(0);
});

test('My Profile offers MFA setup to every role, even those who are not required to enrol', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Set up two-factor authentication' })).toBeVisible();
});

test('My Profile shows the Enabled state and a Remove option when a verified factor exists', async ({ page, app }) => {
  await app.open('organization_administrator', { mfaFactors: VERIFIED_TOTP, aal: 'aal2' });
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
