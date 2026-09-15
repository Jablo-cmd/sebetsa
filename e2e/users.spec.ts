import { test, expect } from '@playwright/test';
import { fulfillJson } from './utils/mockAuth';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, installUsersListMock, installRpcMock, buildProfileRow } from './utils/sebetsaData';

const EMPLOYEE_ID = '44444444-4444-4444-4444-444444444444';

test('admin can view the users directory', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const admin = buildProfileRow({ role: 'organization_administrator', first_name: 'Ada', last_name: 'Admin' });
  await installSebetsaMocks(page, { profile: admin });
  await installUsersListMock(page, [
    admin,
    buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zola', last_name: 'Worker', email: 'zola@sebetsa.example', role: 'employee' }),
  ]);

  await page.goto('/users');
  const main = page.getByRole('main');
  await expect(main.getByRole('heading', { name: 'Users' })).toBeVisible();
  // Scoped to main: the signed-in admin's own name also appears in the
  // sidebar's account identity link.
  await expect(main.getByRole('link', { name: 'Ada Admin' })).toBeVisible();
  await expect(main.getByRole('link', { name: 'Zola Worker' })).toBeVisible();
  await expect(main.getByText('Showing 1–2 of 2')).toBeVisible();
});

test('admin can create a user and sees a one-time temporary password', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const admin = buildProfileRow({ role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: admin });
  await installUsersListMock(page, [admin]);
  await installRpcMock(page, 'admin_create_user', (route) =>
    fulfillJson(route, [{ user_id: '66666666-6666-6666-6666-666666666666', temporary_password: 'Tmp9xQ2vLkZo1==' }]),
  );

  await page.goto('/users');
  await page.getByRole('button', { name: 'Add user' }).click();
  await page.getByLabel('First name').fill('New');
  await page.getByLabel('Last name').fill('Worker');
  await page.getByLabel('Email').fill('new.worker@sebetsa.example');
  await page.locator('#create-user-role').selectOption('employee');
  await page.getByRole('button', { name: 'Create user' }).click();

  await expect(page.getByRole('status')).toHaveText('The account was created successfully.');
  await expect(page.getByText('Tmp9xQ2vLkZo1==')).toBeVisible();

  await page.getByRole('button', { name: 'Done' }).click();
  await expect(page.getByRole('heading', { name: 'Add user' })).toHaveCount(0);
});

test('admin can edit a user', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await installUsersListMock(page, [
    buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zola', last_name: 'Worker', email: 'zola@sebetsa.example', role: 'employee' }),
  ]);
  await page.route('**/rest/v1/profiles*', async (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    await fulfillJson(route, buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zolani', last_name: 'Worker', role: 'employee' }));
  });

  await page.goto('/users');
  await page.getByRole('button', { name: 'Edit' }).click();
  await expect(page.getByRole('heading', { name: 'Edit user' })).toBeVisible();

  await page.getByLabel('First name').fill('Zolani');
  await page.getByRole('button', { name: 'Save changes' }).click();

  await expect(page.getByRole('heading', { name: 'Edit user' })).toHaveCount(0);
});

test('admin can assign a role to an employee', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await installUsersListMock(page, [
    buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zola', last_name: 'Worker', email: 'zola@sebetsa.example', role: 'employee' }),
  ]);
  await installRpcMock(page, 'admin_update_user_role', (route) => fulfillJson(route, null));

  await page.goto('/users');
  await page.getByRole('button', { name: 'Change role' }).click();
  await expect(page.getByRole('heading', { name: 'Change role' })).toBeVisible();
  await expect(page.locator('#change-role-select')).toHaveValue('employee');

  await page.getByRole('button', { name: 'Confirm change' }).click();
  await expect(page.getByRole('heading', { name: 'Change role' })).toHaveCount(0);
});

test('editing a user never sends tenant_id in the update payload', async ({ page }) => {
  // Regression guard for the profiles.tenant_id self-service escalation
  // fix (see supabase/migrations/20260911100400_prevent_direct_tenant_change.sql).
  // The real protection is the DB-side trigger (verified in the RLS
  // harness, supabase/rls-tests/), which blocks this even if the app ever
  // did send it — this test exists so a future change to the edit-user
  // form that starts sending tenant_id fails fast in CI, long before it
  // would reach that trigger in production.
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await installUsersListMock(page, [
    buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zola', last_name: 'Worker', email: 'zola@sebetsa.example', role: 'employee' }),
  ]);

  let patchBody: unknown;
  await page.route('**/rest/v1/profiles*', async (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    patchBody = route.request().postDataJSON();
    await fulfillJson(route, buildProfileRow({ id: EMPLOYEE_ID, first_name: 'Zolani', last_name: 'Worker', role: 'employee' }));
  });

  await page.goto('/users');
  await page.getByRole('button', { name: 'Edit' }).click();
  await page.getByLabel('First name').fill('Zolani');
  await page.getByRole('button', { name: 'Save changes' }).click();

  await expect(page.getByRole('heading', { name: 'Edit user' })).toHaveCount(0);
  expect(patchBody).not.toHaveProperty('tenant_id');
});

test('a role without profile.view_any is blocked from the users directory', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/users');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('link', { name: 'Users' })).toHaveCount(0);
});

test('tenant isolation: a user outside the caller\'s tenant cannot be viewed', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  // RLS scopes profile reads to the caller's own tenant — a cross-tenant id
  // resolves to no row at all, which the client surfaces as "not found"
  // rather than leaking whether the id exists in another tenant.
  await page.route('**/rest/v1/profiles*', async (route) => {
    const url = new URL(route.request().url());
    if (url.searchParams.get('id')?.includes('99999999')) {
      return fulfillJson(route, null);
    }
    return route.fallback();
  });

  await page.goto('/users/99999999-9999-9999-9999-999999999999');
  await expect(page.getByRole('heading', { name: 'User not found' })).toBeVisible();
});
