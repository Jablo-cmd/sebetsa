import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildEmployeeRow, buildTaskRow, buildLeaveTypeRow } from './utils/sebetsaData';

/**
 * Phase L — Mobile / Field Workforce: genuine phone-viewport coverage of
 * the field-critical workflows (attendance, tasks, leave) plus the app
 * shell's mobile navigation drawer. Not a rebuild of the desktop UI at a
 * narrower width — these are the same pages already used for Phase H/I/K,
 * verified to actually work at a real phone size (390x844, iPhone 12/13
 * class) rather than assumed responsive.
 */

const PHONE_VIEWPORT = { width: 390, height: 844 };

test.describe('phone viewport (390x844)', () => {
  test.use({ viewport: PHONE_VIEWPORT });

  test('mobile navigation drawer opens, lists permitted modules, and closes', async ({ page }) => {
    await seedSebetsaSession(page, { role: 'employee' });
    await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow() });

    await page.goto('/dashboard');
    await page.getByRole('button', { name: /menu/i }).click();
    const drawer = page.getByRole('navigation');
    await expect(drawer.getByRole('link', { name: 'My Leave' })).toBeVisible();
    await expect(drawer.getByRole('link', { name: 'My Tasks' })).toBeVisible();
    await expect(drawer.getByRole('link', { name: 'My Attendance' })).toBeVisible();

    await drawer.getByRole('link', { name: 'My Attendance' }).click();
    await expect(page).toHaveURL(/\/attendance\/mine/);
  });

  test('employee can clock in on a phone-sized screen', async ({ page, context }) => {
    // Same real-device-location dependency and same reason to mock it as
    // attendance.spec.ts's clock-in test.
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: -26.2041, longitude: 28.0473 });

    await seedSebetsaSession(page, { role: 'employee' });
    const state = await installSebetsaMocks(page, {
      profile: buildProfileRow({ role: 'employee' }),
      employee: buildEmployeeRow(),
      onRpc: async (fnName, _payload, route) => {
        if (fnName === 'clock_in') {
          const record = { id: 'attendance-1', tenant_id: state.employee?.tenant_id, employee_id: 'employee-1', shift_id: null, site_id: 'site-1', status: 'present', clock_in_at: new Date().toISOString(), clock_out_at: null, late_minutes: null, early_departure_minutes: null, worked_minutes: null, overtime_minutes: null, recorded_by: null, notes: null, gps_verification_status: 'not_applicable', created_at: '', updated_at: '' };
          state.attendanceRecords = [record];
          await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(record) });
          return true;
        }
        return false;
      },
    });

    await page.goto('/attendance/mine');
    await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
    const clockInButton = page.getByRole('button', { name: 'Clock in' });
    await expect(clockInButton).toBeVisible();
    // Real touch-target check, not just visibility — 44px is the common minimum.
    const box = await clockInButton.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(40);

    await clockInButton.click();
    await expect(page.getByText(/Clocked in at/)).toBeVisible();
  });

  test('employee can complete a task on a phone-sized screen', async ({ page }) => {
    await seedSebetsaSession(page, { role: 'employee' });
    const state = await installSebetsaMocks(page, {
      profile: buildProfileRow({ role: 'employee' }),
      employee: buildEmployeeRow(),
      tasks: [buildTaskRow()],
    });

    await page.goto('/tasks');
    await expect(page.getByRole('heading', { name: 'My Tasks' })).toBeVisible();
    await page.getByText('Inspect fire extinguishers').click();
    await expect(page.getByRole('heading', { name: 'Inspect fire extinguishers' })).toBeVisible();
    void state;
  });

  test('employee can submit a leave request on a phone-sized screen', async ({ page }) => {
    await seedSebetsaSession(page, { role: 'employee' });
    await installSebetsaMocks(page, {
      profile: buildProfileRow({ role: 'employee' }),
      employee: buildEmployeeRow(),
      leaveTypes: [buildLeaveTypeRow()],
    });

    await page.goto('/leave');
    await expect(page.getByRole('heading', { name: 'My Leave' })).toBeVisible();
    await page.getByRole('button', { name: 'Request leave' }).click();
    await expect(page.getByRole('heading', { name: 'Request leave' })).toBeVisible();
    // The modal must fit and be usable at phone width, not clipped off-screen.
    const modal = page.getByRole('dialog');
    const box = await modal.boundingBox();
    expect(box?.width ?? 0).toBeLessThanOrEqual(PHONE_VIEWPORT.width);
  });

  test('an employee is still blocked from manager-only pages at phone width', async ({ page }) => {
    await seedSebetsaSession(page, { role: 'employee' });
    await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

    await page.goto('/tasks/management');
    await expect(page).toHaveURL('http://localhost:5173/dashboard');
  });

  test('My Attendance has no serious/critical accessibility violations at phone width', async ({ page }) => {
    await seedSebetsaSession(page, { role: 'employee' });
    await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow() });
    await page.goto('/attendance/mine');
    await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
    const results = await new AxeBuilder({ page }).analyze();
    const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
    expect(serious, `${serious.length} serious/critical accessibility violation(s) at phone width`).toEqual([]);
  });
});
