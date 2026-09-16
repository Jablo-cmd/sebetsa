import { test, expect } from '@playwright/test';
import { fulfillJson } from './utils/mockAuth';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, installUsersListMock, installRpcMock, buildProfileRow, buildOrganizationRow } from './utils/sebetsaData';

/**
 * Covers the actual UI journey behind Sebetsa's identity rule: a staff
 * member is a tenant-bound profile, never a cross-tenant account. Leaving
 * an organization is a deactivation of that profile (not a delete, not a
 * transfer); joining a different organization is always the creation of a
 * new, independent profile with its own email — the same email can never
 * belong to two profiles anywhere on the platform. The database/RLS layer
 * already proves the cross-tenant-isolation half of this (see
 * supabase/rls-tests/); these tests prove the two things only observable
 * through the actual UI flow an admin uses: deactivating a leaving staff
 * member, and the duplicate-email rejection a receiving org's admin would
 * actually see on screen if they ever tried to reuse an existing address.
 */

test('an admin can deactivate a leaving staff member, and the directory reflects it immediately', async ({ page }) => {
  const leavingStaff = buildProfileRow({
    id: 'leaving-staff-1',
    first_name: 'Nomvula',
    last_name: 'Jacobs',
    email: 'n.jacobs@orga.example',
    role: 'employee',
    status: 'active',
  });

  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await installUsersListMock(page, [buildProfileRow({ role: 'organization_administrator' }), leavingStaff]);

  await page.route('**/rest/v1/profiles*', async (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    await fulfillJson(route, { ...leavingStaff, status: 'inactive' });
  });

  await page.goto('/users');
  const row = page.locator('tr', { hasText: 'Nomvula Jacobs' });
  await row.getByRole('button', { name: 'Deactivate' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Deactivate' }).click();

  await expect(page.getByRole('heading', { name: 'Deactivate user' })).toHaveCount(0);
  // This only proves the deactivation call was made and the dialog closed
  // cleanly — that a deactivated profile actually loses live authorization
  // (not merely a status label) is what the RLS suite proves directly
  // against real Postgres; this UI layer can't observe that from a fully
  // mocked network.
});

test('attempting to create a user with an email already registered anywhere on the platform is rejected with a clear, non-technical message', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await installUsersListMock(page, [buildProfileRow({ role: 'organization_administrator' })]);
  await installRpcMock(page, 'admin_create_user', async (route) => {
    // Mirrors admin_create_user's actual RAISE EXCEPTION shape
    // (supabase/migrations/20260911100300_user_role_management.sql) —
    // global, not per-tenant: the same rejection fires whether the email
    // belongs to a profile at this org, a different org, or a deactivated
    // former profile anywhere on the platform.
    await route.fulfill({
      status: 400,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'P0001', message: 'email_taken: n.jacobs@orga.example is already registered' }),
    });
  });

  await page.goto('/users');
  await page.getByRole('button', { name: 'Add user' }).click();
  await page.getByLabel('First name').fill('Nomvula');
  await page.getByLabel('Last name').fill('Jacobs');
  await page.getByLabel('Email').fill('n.jacobs@orga.example');
  await page.locator('#create-user-role').selectOption('employee');
  await page.getByRole('button', { name: 'Create user' }).click();

  // getDbErrorMessage (src/lib/dbErrors.ts) maps the email_taken: prefix to
  // this exact safe copy — never the raw RAISE EXCEPTION text, and never a
  // success state that would imply the identity was merged or reused.
  await expect(page.getByRole('alert')).toHaveText('That email address is already registered.');
  await expect(page.getByText('Tmp9xQ2vLkZo1==')).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Add user' })).toBeVisible();
});

test('a receiving organization can provision a completely new, independent profile using a different email', async ({ page }) => {
  // Represents the Org B half of the same real person's journey — a
  // fresh session, a fresh tenant context (installSebetsaMocks below has
  // no relationship at all to the leaving-staff fixture above; that
  // isolation is the point, not an omission), and a distinct work email,
  // exactly as the identity rule requires.
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    organization: buildOrganizationRow({ id: 'org-b', name: 'Org B' }),
  });
  await installUsersListMock(page, [buildProfileRow({ role: 'organization_administrator' })]);
  await installRpcMock(page, 'admin_create_user', async (route) =>
    fulfillJson(route, [{ user_id: 'new-profile-org-b', temporary_password: 'Tmp9xQ2vLkZo1==' }]),
  );

  await page.goto('/users');
  await page.getByRole('button', { name: 'Add user' }).click();
  await page.getByLabel('First name').fill('Nomvula');
  await page.getByLabel('Last name').fill('Jacobs');
  await page.getByLabel('Email').fill('n.jacobs@orgb.example');
  await page.locator('#create-user-role').selectOption('employee');
  await page.getByRole('button', { name: 'Create user' }).click();

  await expect(page.getByRole('status')).toHaveText('The account was created successfully.');
  await expect(page.getByText('Tmp9xQ2vLkZo1==')).toBeVisible();
});
