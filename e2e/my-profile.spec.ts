import { test, expect } from './utils/test';

test('an employee-linked account sees their own Employee Information', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Employee Information' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByText('BW-0008')).toBeVisible();
  await expect(page.getByText('thabo.nkosi@brightway.example')).toBeVisible();
});

test("an employee never sees another employee's record on My Profile", async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByText('Lerato Mahlangu')).toHaveCount(0);
  await expect(page.getByText('BW-0009')).toHaveCount(0);
});

test('a user with no employee record still gets the Security section, without an empty Employee section', async ({ page, app }) => {
  await app.open('client_user');
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'My Profile' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Employee Information' })).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
});

test('a failure loading the employee record is reported on the page', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('employees', { method: 'GET', status: 500, message: 'database unavailable' });
  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'My Profile' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Thabo Nkosi' })).toHaveCount(0);
});
