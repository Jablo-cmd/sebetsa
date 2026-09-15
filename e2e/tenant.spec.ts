import { test, expect } from '@playwright/test';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildOrganizationRow } from './utils/sebetsaData';

test('shows a friendly notice when the signed-in user has no profile row', async ({ page }) => {
  await seedSebetsaSession(page);
  await installSebetsaMocks(page, { profile: null });

  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Profile not found' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText("couldn't find a profile");
});

test('shows a friendly notice when a non-platform role has no tenant assigned', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ tenant_id: null, first_name: 'Naledi', last_name: 'Dlamini' }),
  });

  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'No organization assigned' })).toBeVisible();
});

test('shows a friendly notice when the assigned organization is inactive', async ({ page }) => {
  await seedSebetsaSession(page);
  await installSebetsaMocks(page, {
    profile: buildProfileRow(),
    organization: buildOrganizationRow({ status: 'inactive', name: 'Auris Facilities Group' }),
  });

  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Organization inactive' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Auris Facilities Group');
});

test('a platform-level role with no tenant reaches the protected home directly', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'platform_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ tenant_id: null, role: 'platform_administrator', first_name: 'Lerato', last_name: 'Molefe' }),
  });

  await page.goto('/');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome back, Lerato' })).toBeVisible();
  // Scoped to main: the sidebar's account identity block also renders the
  // role text ("platform administrator"), so an unscoped query is ambiguous.
  await expect(page.getByRole('main').getByText('platform administrator', { exact: true })).toBeVisible();
});
