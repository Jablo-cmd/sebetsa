import { test, expect } from '@playwright/test';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildEmployeeRow } from './utils/sebetsaData';

test('an employee-linked account sees the Employee Information section', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ first_name: 'Karabo', last_name: 'Mokoena' }),
  });

  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'My Profile' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Employee Information' })).toBeVisible();
  await expect(page.getByText('Karabo Mokoena')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
});

test('an account with no linked employee record still sees the always-present Security section', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'platform_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'platform_administrator' }), employee: null });

  await page.goto('/my-profile');
  await expect(page.getByRole('heading', { name: 'Two-Factor Authentication' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Employee Information' })).toHaveCount(0);
});

test('any authenticated role can reach /my-profile without a permission redirect', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'client_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'client_user' }), employee: null });

  await page.goto('/my-profile');
  await expect(page).toHaveURL('http://localhost:5173/my-profile');
});
