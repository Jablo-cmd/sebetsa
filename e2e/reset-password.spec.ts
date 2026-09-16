import { test, expect } from '@playwright/test';
import { fulfillJson, installAuthMocks } from './utils/mockAuth';
import { buildSebetsaUser, seedSebetsaSession } from './utils/sebetsaAuth';

test('shows an invalid-link notice when there is no recovery session', async ({ page }) => {
  await page.goto('/reset-password');

  await expect(page.getByRole('alert')).toHaveText(
    'This password reset link is invalid or has expired.',
  );
  await page.getByRole('link', { name: 'Request a new reset link' }).click();
  await expect(page).toHaveURL(/\/forgot-password$/);
});

test('validates password confirmation and updates the password', async ({ page }) => {
  await seedSebetsaSession(page);
  await installAuthMocks(page, {
    user: (route) => fulfillJson(route, buildSebetsaUser()),
    logout: (route) => fulfillJson(route, {}, 204),
  });

  await page.goto('/reset-password');
  await expect(page.getByRole('heading', { name: 'Set a new password' })).toBeVisible();

  await page.locator('#new-password').fill('newsecurepass123');
  await page.locator('#confirm-new-password').fill('doesnotmatch');
  await page.getByRole('button', { name: 'Update password' }).click();
  await expect(page.getByText('Passwords do not match')).toBeVisible();

  await page.locator('#confirm-new-password').fill('newsecurepass123');
  await page.getByRole('button', { name: 'Update password' }).click();

  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('status')).toHaveText('Your password has been updated. Please sign in.');
});
