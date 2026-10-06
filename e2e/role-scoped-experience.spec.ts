import { test, expect } from './utils/test';
import type { SignInAs } from './utils/sebetsaFixtures';

/**
 * The sidebar is the contract of what each role can do. These expectations
 * are written out deliberately (not derived from the app's own permission
 * table) so a permission change shows up as a visible diff here.
 */
const COMMON = ['Dashboard', 'My Schedule', 'Notifications', 'Notification Preferences', 'My Profile'];

const NAV: Record<SignInAs, string[]> = {
  platform_administrator: [
    ...COMMON, 'Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations',
    'Schedule', 'Shift Definitions', 'Availability', 'Attendance', 'My Attendance', 'Attendance Corrections', 'My Leave', 'Team Leave', 'Leave Management',
    'Leave Configuration', 'My Tasks', 'Task Management', 'My Documents', 'Employee Documents', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement',
    'My Development', 'Workforce Development', 'Reports', 'Users & Roles', 'Organizations',
  ],
  organization_administrator: [
    ...COMMON, 'Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations',
    'Schedule', 'Shift Definitions', 'Availability', 'Attendance', 'My Attendance', 'Attendance Corrections', 'My Leave', 'Team Leave', 'Leave Management',
    'Leave Configuration', 'My Tasks', 'Task Management', 'My Documents', 'Employee Documents', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement',
    'My Development', 'Workforce Development', 'Reports', 'Users & Roles',
  ],
  operations_manager: [
    ...COMMON, 'Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations',
    'Schedule', 'Shift Definitions', 'Availability', 'Attendance', 'My Attendance', 'Attendance Corrections', 'My Leave', 'Team Leave', 'Leave Management',
    'Leave Configuration', 'My Tasks', 'Task Management', 'My Documents', 'Employee Documents', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement',
    'My Development', 'Workforce Development', 'Reports',
  ],
  regional_manager: [
    ...COMMON, 'Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations',
    'Schedule', 'Shift Definitions', 'Availability', 'Attendance', 'My Attendance', 'Attendance Corrections', 'My Leave', 'Team Leave', 'Leave Management',
    'My Tasks', 'Task Management', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement', 'Reports',
  ],
  site_manager: [
    ...COMMON, 'Regions', 'Clients', 'Sites', 'Contracts', 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations',
    'Schedule', 'Shift Definitions', 'Availability', 'Attendance', 'My Attendance', 'Attendance Corrections', 'My Leave', 'Team Leave', 'My Tasks',
    'Task Management', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement', 'Reports',
  ],
  supervisor: [
    ...COMMON, 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations', 'Schedule', 'Shift Definitions', 'Availability',
    'Attendance', 'My Attendance', 'Attendance Corrections', 'My Tasks', 'Task Management', 'Incidents', 'Compliance', 'Assets', 'Inventory', 'Procurement', 'Reports',
  ],
  hr_user: [
    ...COMMON, 'Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Site Operations', 'My Leave', 'Team Leave', 'Leave Management',
    'Leave Configuration', 'My Documents', 'Employee Documents', 'My Development', 'Workforce Development', 'Reports', 'Users & Roles',
  ],
  employee: [
    ...COMMON, 'Schedule', 'Availability', 'Attendance', 'My Attendance', 'My Leave', 'Team Leave', 'My Tasks', 'My Documents', 'Incidents', 'Procurement', 'My Development',
  ],
  employee_two: [
    ...COMMON, 'Schedule', 'Availability', 'Attendance', 'My Attendance', 'My Leave', 'Team Leave', 'My Tasks', 'My Documents', 'Incidents', 'Procurement', 'My Development',
  ],
  client_user: [...COMMON],
};

const sidebar = (page: import('@playwright/test').Page) => page.getByRole('navigation').first();

test('a platform administrator sees every organisation and can switch into one', async ({ page, app }) => {
  await app.open('platform_administrator');
  await page.goto('/organizations');
  await expect(page.getByRole('row', { name: /Brightway Facilities/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Rival Services/ })).toBeVisible();
});

test('the staff shell never renders a "Soon" or disabled placeholder nav item', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/dashboard');
  await expect(sidebar(page).getByText(/soon/i)).toHaveCount(0);
  await expect(sidebar(page).locator('[aria-disabled="true"], [disabled]')).toHaveCount(0);
});

for (const role of Object.keys(NAV) as SignInAs[]) {
  test(`${role} sees exactly their role's sidebar and every link opens a working page`, async ({ page, app }) => {
    test.setTimeout(120_000);
    await app.open(role);
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();

    if (role === 'platform_administrator') {
      // Platform-level users have no organisation until they pick one.
      await page.goto('/organizations');
      await page.getByRole('row', { name: /Brightway Facilities/ }).getByRole('button', { name: 'Switch to this organization' }).click();
      await expect(page).toHaveURL(/\/dashboard$/);
      await expect(page.getByText('Brightway Facilities (Demo)').first()).toBeVisible();
    }

    const links = await sidebar(page).getByRole('link').evaluateAll((els) => els.map((el) => ({ label: (el.textContent ?? '').trim(), href: el.getAttribute('href') ?? '' })));
    expect(links.map((l) => l.label).sort()).toEqual([...NAV[role]].sort());

    for (const link of links) {
      await page.goto(link.href);
      await expect(page, `${role}: ${link.label} (${link.href}) must not bounce to the dashboard`).toHaveURL(new RegExp(`${link.href === '/dashboard' ? '/dashboard' : link.href}$`));
      await expect(page.getByRole('main'), `${role}: ${link.label} must render inside the layout`).toBeVisible();
      await expect(page.getByRole('heading', { level: 1 }).first(), `${role}: ${link.label} must have a page heading`).toBeVisible();
      await expect(page.getByRole('alert'), `${role}: ${link.label} must not show an error`).toHaveCount(0);
    }
  });
}

test('route guards block hidden areas on direct navigation', async ({ page, app }) => {
  await app.open('employee');
  for (const path of ['/users', '/employees', '/regions', '/reports', '/leave/management', '/leave/configuration', '/tasks/management', '/organizations', '/documents/manage', '/compliance', '/assets', '/schedule/definitions']) {
    await page.goto(path);
    await expect(page, `${path} must be blocked for an employee`).toHaveURL('http://localhost:5173/dashboard');
  }
});

test('a role with employee.view but not user management cannot reach /users by URL', async ({ page, app }) => {
  await app.open('supervisor');
  await page.goto('/employees');
  await expect(page).toHaveURL(/\/employees$/);
  await page.goto('/users');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('only a platform administrator can open the organisations area', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/organizations');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
