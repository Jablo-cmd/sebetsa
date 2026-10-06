import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('redirects an unverified signed-in user to /verify-email and allows resending', async ({ page, app }) => {
  const backend = await app.open('employee', { signedIn: false });
  await app.seedRawSession({ id: PERSONAS.employee.profileId, role: 'employee', tenantId: ID.org, email: PERSONAS.employee.email, emailConfirmed: false });

  await page.goto('/');
  await expect(page).toHaveURL(/\/verify-email$/);
  await expect(page.getByRole('heading', { name: 'Verify your email' })).toBeVisible();
  await expect(page.getByText(PERSONAS.employee.email)).toBeVisible();

  await page.getByRole('button', { name: 'Resend verification email' }).click();
  await expect(page.getByRole('status')).toHaveText('Verification email sent. Please check your inbox.');
  await expect(page.getByRole('button', { name: /Resend available in \d+s/ })).toBeVisible();
  expect(backend.authCalls.filter((c) => c.path === '/auth/v1/resend')).toHaveLength(1);
});

test('sends a verified signed-in user straight to the protected home', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/verify-email');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome, Thabo' })).toBeVisible();
});
