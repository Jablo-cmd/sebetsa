import { test, expect } from '@playwright/test';
import { fulfillAuthError, fulfillJson, installAuthMocks } from './utils/mockAuth';
import { buildSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildOrganizationRow } from './utils/sebetsaData';

test('redirects an unauthenticated visitor from "/" to "/login"', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('heading', { name: 'Sign in to your account' })).toBeVisible();
});

test('shows validation errors when submitting an empty form', async ({ page }) => {
  await page.goto('/login');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page.getByText('Email is required')).toBeVisible();
  await expect(page.getByText('Password is required')).toBeVisible();
});

test('shows a friendly error for invalid credentials', async ({ page }) => {
  await installAuthMocks(page, {
    token: (route) => fulfillAuthError(route, 'invalid_credentials', 'Invalid login credentials'),
  });

  await page.goto('/login');
  await page.getByLabel('Email address').fill('admin@sebetsa.example');
  await page.locator('#password').fill('wrong-password');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page.getByRole('alert')).toHaveText('Incorrect email or password.');
  await expect(page).toHaveURL(/\/login$/);
});

test('signs in successfully, reaches the protected home, and signs out', async ({ page }) => {
  const organization = buildOrganizationRow({ name: 'Auris Facilities Group' });
  const profile = buildProfileRow({ first_name: 'Priya', last_name: 'Naidoo', role: 'employee' });

  // installSebetsaMocks registers its own catch-all auth/v1 route (a
  // harmless 200 {} fallback for anything not explicitly handled) —
  // installed first so installAuthMocks' more specific /token handler
  // (registered after) takes priority for that one request, matching
  // Playwright's last-registered-wins routing order.
  await installSebetsaMocks(page, { organization, profile });
  await installAuthMocks(page, {
    token: (route) => fulfillJson(route, buildSebetsaSession({ role: 'employee', email: profile.email as string })),
    logout: (route) => fulfillJson(route, {}, 204),
  });

  await page.goto('/login');
  await page.getByLabel('Email address').fill('admin@sebetsa.example');
  await page.locator('#password').fill('correct-password');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome, Priya' })).toBeVisible();
  await expect(page.getByText('Priya Naidoo').first()).toBeVisible();
  await expect(page.getByText('employee at Auris Facilities Group')).toBeVisible();

  await page.getByRole('button', { name: /Priya Naidoo/ }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('toggles password visibility', async ({ page }) => {
  await page.goto('/login');
  const passwordInput = page.locator('#password');
  await passwordInput.fill('supersecret123');

  await expect(passwordInput).toHaveAttribute('type', 'password');
  await page.getByRole('button', { name: 'Show password' }).click();
  await expect(passwordInput).toHaveAttribute('type', 'text');
  await page.getByRole('button', { name: 'Hide password' }).click();
  await expect(passwordInput).toHaveAttribute('type', 'password');
});
