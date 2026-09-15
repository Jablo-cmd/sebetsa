import { test, expect, type Page } from '@playwright/test';
import { seedSebetsaSession, type SebetsaUserRole } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow } from './utils/sebetsaData';

/**
 * Proves the sidebar actually reflects `resolveNavForRole`
 * (src/features/rbac/constants/navigation.ts) end to end for four roles
 * spanning the permission spectrum — a minimal self-service role
 * (employee), an HR-tier administrative role (hr_user), a broad
 * operational role (site_manager), and the full-access role
 * (platform_administrator). There is no "show but disable" path in this
 * app: an item a role cannot use must be absent from the DOM entirely, not
 * merely disabled, so every assertion below checks link presence/absence
 * rather than a disabled attribute.
 */

const nav = (page: Page) => page.locator('nav[aria-label="Main"]');

async function seedRole(page: Page, role: SebetsaUserRole) {
  await seedSebetsaSession(page, { role });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role }) });
  await page.goto('/dashboard');
}

test('employee sees only self-service navigation, not org/admin/management items', async ({ page }) => {
  await seedRole(page, 'employee');

  // Always-present items (ungated, or covered by employee's own permissions).
  for (const label of ['Dashboard', 'My Schedule', 'My Attendance', 'My Leave', 'My Tasks', 'My Documents', 'Incidents', 'My Development', 'Notifications', 'My Profile']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toBeVisible();
  }

  // Requires permissions employee does not hold.
  for (const label of [
    'Regions',
    'Clients',
    'Sites',
    'Contracts',
    'Employees',
    'Teams',
    'Departments',
    'Positions',
    'Site Assignments',
    'Attendance Corrections',
    'Leave Management',
    'Task Management',
    'Employee Documents',
    'Compliance',
    'Assets',
    'Inventory',
    'Workforce Development',
    'Reports',
    'Users & Roles',
    'Organizations',
  ]) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toHaveCount(0);
  }
});

test('hr_user sees workforce administration and user management, not org structure or operational scheduling', async ({ page }) => {
  await seedRole(page, 'hr_user');

  for (const label of ['Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Leave Management', 'Leave Configuration', 'Employee Documents', 'Workforce Development', 'Reports', 'Users & Roles']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toBeVisible();
  }

  // hr_user holds no org_structure.view, scheduling.view, attendance.view,
  // task.view, incident.view, compliance.view, asset/inventory/procurement
  // view, or tenant.switch.
  for (const label of ['Regions', 'Clients', 'Sites', 'Contracts', 'Schedule', 'Attendance', 'Attendance Corrections', 'My Tasks', 'Task Management', 'Incidents', 'Compliance', 'Assets', 'Organizations']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toHaveCount(0);
  }
});

test('site_manager sees broad operational access but not HR administration or platform admin items', async ({ page }) => {
  await seedRole(page, 'site_manager');

  for (const label of ['Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Site Assignments', 'Schedule', 'Shift Definitions', 'Attendance', 'Attendance Corrections', 'My Tasks', 'Task Management', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement', 'Reports']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toBeVisible();
  }

  // site_manager holds no leave.approve/manage, document.view/manage,
  // development.*, profile.manage_any, or tenant.switch.
  for (const label of ['Leave Management', 'Leave Configuration', 'Employee Documents', 'Workforce Development', 'Users & Roles', 'Organizations']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toHaveCount(0);
  }
});

test('platform_administrator sees the full navigation including tenant switching and user management', async ({ page }) => {
  await seedRole(page, 'platform_administrator');

  for (const label of ['Regions', 'Employees', 'Site Assignments', 'Schedule', 'Leave Management', 'Task Management', 'Employee Documents', 'Compliance', 'Assets', 'Workforce Development', 'Reports', 'Users & Roles', 'Organizations']) {
    await expect(nav(page).getByRole('link', { name: label, exact: true })).toBeVisible();
  }
});

test('a role change is reflected immediately on next load — no stale cross-role navigation state', async ({ page }) => {
  await seedRole(page, 'employee');
  await expect(nav(page).getByRole('link', { name: 'Users & Roles', exact: true })).toHaveCount(0);

  await seedRole(page, 'platform_administrator');
  await expect(nav(page).getByRole('link', { name: 'Users & Roles', exact: true })).toBeVisible();
});
