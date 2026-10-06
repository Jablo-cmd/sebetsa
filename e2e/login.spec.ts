import { test, expect } from './utils/test';
import { PERSONAS } from './utils/sebetsaFixtures';

test('redirects an unauthenticated visitor from "/" to "/login"', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/');
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('heading', { name: 'Sign in to your account' })).toBeVisible();
});

test('shows validation errors when submitting an empty form', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/login');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page.getByText('Email is required')).toBeVisible();
  await expect(page.getByText('Password is required')).toBeVisible();
});

test('shows a friendly error for invalid credentials and sends no session request', async ({ page, app }) => {
  const backend = await app.open('employee', { signedIn: false });
  await page.goto('/login');
  await page.getByLabel('Email address').fill(PERSONAS.employee.email);
  await page.locator('#password').fill('wrong-password');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page.getByRole('alert')).toHaveText('Incorrect email or password.');
  await expect(page).toHaveURL(/\/login$/);
  expect(backend.requests.filter((r) => r.table === 'profiles')).toEqual([]);
});

test('signs in as an employee, lands on a role-appropriate dashboard, and signs out', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/login');
  await page.getByLabel('Email address').fill(PERSONAS.employee.email);
  await page.locator('#password').fill('Correct-Horse-1!');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome, Thabo' })).toBeVisible();
  await expect(page.getByText('employee at Brightway Facilities (Demo)')).toBeVisible();

  await page.getByRole('button', { name: /Thabo Nkosi/ }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect(page).toHaveURL(/\/login$/);
});

test('toggles password visibility', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/login');
  const passwordInput = page.locator('#password');
  await passwordInput.fill('supersecret123');

  await expect(passwordInput).toHaveAttribute('type', 'password');
  await page.getByRole('button', { name: 'Show password' }).click();
  await expect(passwordInput).toHaveAttribute('type', 'text');
  await page.getByRole('button', { name: 'Hide password' }).click();
  await expect(passwordInput).toHaveAttribute('type', 'password');
});
