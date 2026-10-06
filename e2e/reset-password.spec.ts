import { test, expect } from './utils/test';

test('shows an invalid-link notice when there is no recovery session', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/reset-password');

  await expect(page.getByRole('alert')).toHaveText('This password reset link is invalid or has expired.');
  await page.getByRole('link', { name: 'Request a new reset link' }).click();
  await expect(page).toHaveURL(/\/forgot-password$/);
});

test('validates password confirmation and updates the password', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/reset-password');
  await expect(page.getByRole('heading', { name: 'Set a new password' })).toBeVisible();

  await page.locator('#new-password').fill('newsecurepass123');
  await page.locator('#confirm-new-password').fill('doesnotmatch');
  await page.getByRole('button', { name: 'Update password' }).click();
  await expect(page.getByText('Passwords do not match')).toBeVisible();
  expect(backend.authCalls.filter((c) => c.method === 'PUT')).toEqual([]);

  await page.locator('#confirm-new-password').fill('newsecurepass123');
  await page.getByRole('button', { name: 'Update password' }).click();

  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('status')).toHaveText('Your password has been updated. Please sign in.');
  const update = backend.authCalls.filter((c) => c.path === '/auth/v1/user' && c.method === 'PUT');
  expect(update).toHaveLength(1);
  expect(update[0].body).toMatchObject({ password: 'newsecurepass123' });
});
