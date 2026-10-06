import { test, expect } from './utils/test';
import { PERSONAS } from './utils/sebetsaFixtures';

test('navigates from login to forgot-password and back', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/login');
  await page.getByRole('link', { name: 'Forgot password?' }).click();
  await expect(page).toHaveURL(/\/forgot-password$/);
  await expect(page.getByRole('heading', { name: 'Reset your password' })).toBeVisible();

  await page.getByRole('link', { name: 'Back to sign in' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('shows a generic confirmation after requesting a reset link', async ({ page, app }) => {
  const backend = await app.open('employee', { signedIn: false });
  await page.goto('/forgot-password');
  await page.getByLabel('Email address').fill(PERSONAS.employee.email);
  await page.getByRole('button', { name: 'Send reset link' }).click();

  await expect(page.getByRole('status')).toContainText("we've sent a link to reset your password");
  const recover = backend.authCalls.filter((c) => c.path === '/auth/v1/recover');
  expect(recover).toHaveLength(1);
});

test('surfaces rate-limit errors from the reset request', async ({ page, app }) => {
  const backend = await app.open('employee', { signedIn: false });
  backend.recoverRateLimited = true;
  await page.goto('/forgot-password');
  await page.getByLabel('Email address').fill(PERSONAS.employee.email);
  await page.getByRole('button', { name: 'Send reset link' }).click();

  await expect(page.getByRole('alert')).toHaveText('Too many requests. Please wait a moment and try again.');
});
