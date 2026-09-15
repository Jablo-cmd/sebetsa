import { test, expect } from '@playwright/test';
import { fulfillJson, installAuthMocks } from './utils/mockAuth';
import { buildSebetsaUser, seedSebetsaSession } from './utils/sebetsaAuth';

test('shows an invalid-invitation notice when there is no recovery session', async ({ page }) => {
  await page.goto('/activate-account');

  await expect(page.getByRole('alert')).toHaveText('This invitation link is invalid or has expired.');
  await page.getByRole('link', { name: 'Go to sign in' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('a new employee with a valid recovery session can set a password and activate their account', async ({ page }) => {
  // ActivateAccountForm reuses the same recovery-session flow as password
  // reset (see the form's own doc-comment) — a session being present at
  // all is what AuthProvider's PASSWORD_RECOVERY handling establishes;
  // seeding a session here stands in for that.
  await seedSebetsaSession(page, { role: 'employee' });
  await installAuthMocks(page, {
    user: (route) => fulfillJson(route, buildSebetsaUser({ role: 'employee' })),
    logout: (route) => fulfillJson(route, {}, 204),
  });

  await page.goto('/activate-account');

  await expect(page.getByRole('heading', { name: 'Activate your account' })).toBeVisible();
  await page.locator('#new-password').fill('newsecurepass123');
  await page.locator('#confirm-new-password').fill('newsecurepass123');
  await page.getByRole('button', { name: 'Activate my account' }).click();

  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('status')).toHaveText('Your account is now active. Please sign in.');
});
