import { test, expect } from '@playwright/test';
import { fulfillAuthError, fulfillJson, installAuthMocks } from './utils/mockAuth';

test('navigates from login to forgot-password and back', async ({ page }) => {
  await page.goto('/login');
  await page.getByRole('link', { name: 'Forgot password?' }).click();
  await expect(page).toHaveURL(/\/forgot-password$/);
  await expect(page.getByRole('heading', { name: 'Reset your password' })).toBeVisible();

  await page.getByRole('link', { name: 'Back to sign in' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('shows a generic confirmation after requesting a reset link', async ({ page }) => {
  await installAuthMocks(page, {
    recover: (route) => fulfillJson(route, {}),
  });

  await page.goto('/forgot-password');
  await page.getByLabel('Email address').fill('admin@sebetsa.example');
  await page.getByRole('button', { name: 'Send reset link' }).click();

  await expect(page.getByRole('status')).toContainText("we've sent a link to reset your password");
});

test('surfaces rate-limit errors from the reset request', async ({ page }) => {
  await installAuthMocks(page, {
    recover: (route) => fulfillAuthError(route, 'over_email_send_rate_limit', 'Rate limit exceeded'),
  });

  await page.goto('/forgot-password');
  await page.getByLabel('Email address').fill('admin@sebetsa.example');
  await page.getByRole('button', { name: 'Send reset link' }).click();

  await expect(page.getByRole('alert')).toHaveText('Too many requests. Please wait a moment and try again.');
});
