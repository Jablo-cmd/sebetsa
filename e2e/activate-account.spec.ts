import { test, expect } from './utils/test';

test('shows an invalid-invitation notice when there is no recovery session', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/activate-account');

  await expect(page.getByRole('alert')).toHaveText('This invitation link is invalid or has expired.');
  await expect(page.getByLabel('Choose a password')).toHaveCount(0);
  await page.getByRole('link', { name: 'Go to sign in' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('an invited user sets a password, is signed out, and is told to sign in', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/activate-account');
  await expect(page.getByRole('heading', { name: 'Activate your account' })).toBeVisible();

  await page.locator('#new-password').fill('short');
  await page.locator('#confirm-new-password').fill('short');
  await page.getByRole('button', { name: 'Activate my account' }).click();
  await expect(page.getByRole('alert').or(page.getByText(/at least 8 characters/i)).first()).toBeVisible();
  expect(backend.authCalls.filter((c) => c.method === 'PUT')).toEqual([]);

  await page.locator('#new-password').fill('A-strong-passphrase-1');
  await page.locator('#confirm-new-password').fill('A-strong-passphrase-1');
  await page.getByRole('button', { name: 'Activate my account' }).click();

  await expect(page).toHaveURL(/\/login$/);
  const updates = backend.authCalls.filter((c) => c.path === '/auth/v1/user' && c.method === 'PUT');
  expect(updates).toHaveLength(1);
  expect(updates[0].body).toMatchObject({ password: 'A-strong-passphrase-1' });
  expect(backend.authCalls.some((c) => c.path === '/auth/v1/logout')).toBe(true);
  await expect(page.getByRole('status')).toHaveText('Your account is now active. Please sign in.');
});
