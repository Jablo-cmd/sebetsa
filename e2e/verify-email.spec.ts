import { test, expect } from '@playwright/test';
import { fulfillJson, installAuthMocks } from './utils/mockAuth';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow } from './utils/sebetsaData';

test('redirects an unverified signed-in user to /verify-email and allows resending', async ({ page }) => {
  await seedSebetsaSession(page, { emailConfirmed: false });
  await installAuthMocks(page, {
    resend: (route) => fulfillJson(route, {}),
  });

  await page.goto('/');
  await expect(page).toHaveURL(/\/verify-email$/);
  await expect(page.getByRole('heading', { name: 'Verify your email' })).toBeVisible();
  await expect(page.getByText('test.user@sebetsa.example')).toBeVisible();

  await page.getByRole('button', { name: 'Resend verification email' }).click();
  await expect(page.getByRole('status')).toHaveText('Verification email sent. Please check your inbox.');
  await expect(page.getByRole('button', { name: /Resend available in \d+s/ })).toBeVisible();
});

test('sends a verified signed-in user straight to the protected home', async ({ page }) => {
  await seedSebetsaSession(page, { emailConfirmed: true, role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee', first_name: 'Ada' }),
  });

  await page.goto('/verify-email');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome, Ada' })).toBeVisible();
});
