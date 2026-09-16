import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildAttendanceRecordRow,
  buildPatrolRouteRow,
  buildPatrolRunRow,
  buildPatrolCheckpointScanRow,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/**
 * Domain 13 — GPS Field Presence + Guard Tours E2E coverage. Real UI,
 * mocked REST/RPC responses shaped exactly like the real server would
 * respond (an out-of-geofence clock-in is still recorded, never rejected;
 * a wrong-sequence/duplicate scan is evidence, not an error) — the
 * server-authoritative business logic itself is what
 * supabase/rls-tests/domain13_gps_guard_tours.sql exercises against a real
 * Postgres engine; this file proves the UI presents those real outcomes
 * correctly.
 */

test('GPS clock-in outside the geofence is recorded, not silently accepted, and offers an exception request', async ({ page, context }) => {
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: -26.3, longitude: 28.2 }); // far from the configured site geofence

  // The employee-facing half of a supervisor's later decision — otherwise
  // invisible once the submission confirmation dismisses.
  const myExceptions: Record<string, unknown>[] = [];

  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    attendanceRecords: [],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'clock_in') {
        const record = buildAttendanceRecordRow({ clock_in_at: new Date().toISOString(), status: 'unconfirmed', gps_verification_status: 'outside_geofence' });
        state.attendanceRecords = [record];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(record) });
        return true;
      }
      if (fnName === 'request_attendance_location_exception') {
        const exception = { id: 'exception-1', tenant_id: state.employee?.tenant_id, attendance_record_id: 'attendance-1', employee_id: 'employee-1', reason: 'GPS was inaccurate near the entrance', status: 'pending', reviewed_by: null, reviewed_at: null, review_notes: null, created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
        myExceptions.push(exception);
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(exception) });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/attendance_location_exceptions*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(myExceptions) });
  });

  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Clock in' }).click();

  // Not a rejection — attendance is recorded, but the real verification
  // status is shown, never silently upgraded to "verified".
  await expect(page.getByText('Outside site geofence')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Request a location exception' })).toBeVisible();

  await page.getByRole('button', { name: 'Request a location exception' }).click();
  await page.getByLabel('Why should this be reviewed?').fill('GPS was inaccurate near the entrance');
  await page.getByRole('button', { name: 'Submit' }).click();

  await expect(page.getByText('Your location exception request has been submitted for supervisor review.')).toBeVisible();
  await expect(page.getByText('Your GPS exception requests')).toBeVisible();
  await expect(page.getByText('GPS was inaccurate near the entrance')).toBeVisible();
  await expect(page.getByText('pending', { exact: true })).toBeVisible();
});

test('supervisor can review and approve a pending GPS exception', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'decide_attendance_location_exception') {
        expect(payload.p_approve).toBe(true);
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ id: payload.p_exception_id, status: 'approved', reviewed_at: new Date().toISOString() }),
        });
        return true;
      }
      return false;
    },
  });

  // Direct REST GET for attendance_location_exceptions isn't in the shared
  // mock's table list — attendanceService.getPendingLocationExceptions
  // falls through to the generic "unrecognized GET → []" default, so seed
  // it via a page.route override instead.
  await page.route('**/rest/v1/attendance_location_exceptions*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'exception-1', tenant_id: '22222222-2222-2222-2222-222222222222', attendance_record_id: 'attendance-1', employee_id: 'employee-2', reason: 'Poor GPS reception at the loading bay', status: 'pending', reviewed_by: null, reviewed_at: null, review_notes: null, created_at: '2026-09-14T08:00:00Z', updated_at: '2026-09-14T08:00:00Z' },
      ]),
    });
  });

  await page.goto('/attendance/location-exceptions');
  await expect(page.getByRole('heading', { name: 'Location Exceptions' })).toBeVisible();
  await expect(page.getByText('Poor GPS reception at the loading bay')).toBeVisible();

  await page.getByRole('button', { name: 'Review' }).click();
  await page.getByRole('button', { name: 'Approve' }).click();

  // The reviewed request drops out of the pending queue.
  await expect(page.getByText('Poor GPS reception at the loading bay')).not.toBeVisible();
});

test('a self-approval rejection from the server surfaces as a real error, never a false success', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'decide_attendance_location_exception') {
        // Exactly what decide_attendance_location_exception() raises for a
        // self-approval attempt — see supabase/migrations/20260921090000.
        await route.fulfill({
          status: 400,
          contentType: 'application/json',
          body: JSON.stringify({ message: 'insufficient_privilege: cannot decide your own attendance location exception', code: 'P0001' }),
        });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/attendance_location_exceptions*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'exception-1', tenant_id: '22222222-2222-2222-2222-222222222222', attendance_record_id: 'attendance-1', employee_id: 'employee-1', reason: 'My own request', status: 'pending', reviewed_by: null, reviewed_at: null, review_notes: null, created_at: '2026-09-14T08:00:00Z', updated_at: '2026-09-14T08:00:00Z' },
      ]),
    });
  });

  await page.goto('/attendance/location-exceptions');
  await page.getByRole('button', { name: 'Review' }).click();
  await page.getByRole('button', { name: 'Approve' }).click();

  // Never a silent/false success: the row must remain in the queue and a
  // real error must be shown.
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.getByText('My own request')).toBeVisible();
});

test('employee can start a patrol, scan checkpoints (including a wrong-order and a duplicate), and complete it', async ({ page, context }) => {
  // scan_checkpoint (like clock_in/clock_out) reads a device location first
  // — grant + mock it for the same reason as attendance.spec.ts's clock-in
  // test (this sandbox's egress policy blocks the real browser geolocation
  // network provider).
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: -26.2041, longitude: 28.0473 });

  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    patrolRoutes: [buildPatrolRouteRow()],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'start_patrol') {
        const run = buildPatrolRunRow();
        state.patrolRuns = [run];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(run) });
        return true;
      }
      if (fnName === 'scan_checkpoint') {
        const code = payload.p_checkpoint_code as string;
        const alreadyScanned = (state.patrolCheckpointScans ?? []).some((s) => s.scanned_code === code && s.verification_result === 'valid');
        let result: string;
        if (alreadyScanned) result = 'duplicate';
        else if (code === 'CP-B' && (state.patrolCheckpointScans ?? []).length === 0) result = 'wrong_sequence';
        else result = 'valid';

        const scan = buildPatrolCheckpointScanRow({
          id: `scan-${(state.patrolCheckpointScans?.length ?? 0) + 1}`,
          scanned_code: code,
          verification_result: result,
          sequence_number: (state.patrolCheckpointScans?.length ?? 0) + 1,
        });
        state.patrolCheckpointScans = [...(state.patrolCheckpointScans ?? []), scan];

        const run = { ...(state.patrolRuns?.[0] ?? buildPatrolRunRow()) };
        if (result === 'valid') run.scanned_checkpoint_count = ((run.scanned_checkpoint_count as number) ?? 0) + 1;
        state.patrolRuns = [run];

        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([{ scan, run }]) });
        return true;
      }
      if (fnName === 'complete_patrol') {
        const run = { ...(state.patrolRuns?.[0] ?? buildPatrolRunRow()), status: 'completed', completed_at: new Date().toISOString() };
        state.patrolRuns = [run];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(run) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/patrols');
  await expect(page.getByRole('heading', { name: 'My Patrols' })).toBeVisible();

  await page.getByLabel('Choose a route').selectOption('route-1');
  await page.getByRole('button', { name: 'Start patrol' }).click();
  await expect(page.getByText('Patrol in progress')).toBeVisible();

  // Wrong order: CP-B before CP-A.
  await page.getByLabel('Checkpoint code').fill('CP-B');
  await page.getByRole('button', { name: 'Scan' }).click();
  await expect(page.getByText('Wrong order')).toBeVisible();

  // Correct: CP-A.
  await page.getByLabel('Checkpoint code').fill('CP-A');
  await page.getByRole('button', { name: 'Scan' }).click();
  await expect(page.getByText('Scanned', { exact: true })).toBeVisible();

  // Duplicate: CP-A again.
  await page.getByLabel('Checkpoint code').fill('CP-A');
  await page.getByRole('button', { name: 'Scan' }).click();
  await expect(page.getByText('Already scanned')).toBeVisible();

  await page.getByRole('button', { name: 'Complete patrol' }).click();
  // start_patrol/complete_patrol calls refetch the active-run hook, which
  // (with no more in-progress run) returns to the route picker.
  await expect(page.getByRole('button', { name: 'Start patrol' })).toBeVisible();
});

test('Patrol Oversight shows real, live aggregate figures, never hardcoded stats', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'get_patrol_summary') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([{ active_patrols: 3, completed_patrols: 11, incomplete_patrols: 2, missed_checkpoints: 1, late_checkpoints: 4, exception_rate: 6.5 }]),
        });
        return true;
      }
      return false;
    },
  });

  await page.goto('/patrols/oversight');
  await expect(page.getByRole('heading', { name: 'Patrol Oversight' })).toBeVisible();
  await expect(page.getByText('3', { exact: true })).toBeVisible();
  await expect(page.getByText('11', { exact: true })).toBeVisible();
  await expect(page.getByText('6.5', { exact: true })).toBeVisible();
});

test('an employee is blocked from Patrol Oversight (command_centre.view only)', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/patrols/oversight');
  await expect(page).toHaveURL(/\/dashboard/);
});

test('Location Exceptions has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await page.route('**/rest/v1/attendance_location_exceptions*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.goto('/attendance/location-exceptions');
  await expect(page.getByRole('heading', { name: 'Location Exceptions' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Patrol Oversight has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'get_patrol_summary') {
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([{}]) });
        return true;
      }
      return false;
    },
  });
  await page.goto('/patrols/oversight');
  await expect(page.getByRole('heading', { name: 'Patrol Oversight' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('My Patrols has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    patrolRoutes: [buildPatrolRouteRow()],
  });
  await page.goto('/patrols');
  await expect(page.getByRole('heading', { name: 'My Patrols' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
