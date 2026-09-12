import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildLeaveRequestRow,
  buildLeaveTypeRow,
  buildProfileRow,
  buildEmployeeRow,
} from './utils/sebetsaData';

/** Same practical baseline as e2e/accessibility.spec.ts (automated
 * axe-core scan, not a full manual audit) — serious/critical violations
 * only, applied to the four Phase H Leave pages. */
async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/**
 * Genuine Sebetsa Leave & Absence E2E coverage — built on the real
 * localStorage session key, table names, and role model (see
 * e2e/utils/sebetsaAuth.ts / sebetsaData.ts), replacing the stale
 * Funda360-shaped e2e/leave-requests.spec.ts (removed). Every assertion
 * here exercises the actual rendered UI against mocked REST/RPC responses
 * — no database-internal state is asserted through the UI; that
 * coverage belongs to supabase/rls-tests/leave.sql, not here.
 */

test('employee can submit a leave request, see it pending, and cancel it', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    leaveTypes: [buildLeaveTypeRow()],
    leaveRequests: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'submit_leave_request') {
        const created = buildLeaveRequestRow({
          id: 'new-request-1',
          leave_type_id: payload.p_leave_type_id,
          start_date: payload.p_start_date,
          end_date: payload.p_end_date,
          reason: payload.p_reason ?? null,
          status: 'pending',
        });
        state.leaveRequests = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      if (fnName === 'cancel_leave_request') {
        const cancelled = { ...(state.leaveRequests?.[0] ?? buildLeaveRequestRow()), status: 'cancelled', cancelled_at: '2026-09-12T00:00:00Z', cancelled_by: '11111111-1111-1111-1111-111111111111' };
        state.leaveRequests = [cancelled];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(cancelled) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/leave');
  await expect(page.getByRole('heading', { name: 'My Leave' })).toBeVisible();
  await expect(page.getByText("You haven't requested any leave yet.")).toBeVisible();

  await page.getByRole('button', { name: 'Request leave' }).click();
  await expect(page.getByRole('heading', { name: 'Request leave' })).toBeVisible();

  await page.getByLabel(/Leave type/).selectOption('leave-type-annual');
  await page.getByLabel('Start date').fill('2026-09-20');
  await page.getByLabel('End date').fill('2026-09-22');
  await page.getByLabel('Reason').fill('Family trip');
  await page.getByRole('button', { name: 'Submit request' }).click();

  await expect(page.getByRole('heading', { name: 'Request leave' })).toHaveCount(0);
  await expect(page.getByText('Pending')).toBeVisible();
  await expect(page.getByText('Family trip')).toBeVisible();

  await page.getByRole('button', { name: 'Cancel' }).click();
  await expect(page.getByText('Cancelled')).toBeVisible();
});

test('organization_administrator can approve a pending leave request', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const pending = buildLeaveRequestRow({ status: 'pending' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    leaveTypes: [buildLeaveTypeRow()],
    leaveRequests: [pending],
    affectedShifts: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'approve_leave_request') {
        const approved = {
          ...pending,
          status: 'approved',
          decided_by: '11111111-1111-1111-1111-111111111111',
          decided_at: '2026-09-12T00:00:00Z',
          decision_notes: payload.p_decision_notes ?? null,
        };
        state.leaveRequests = [approved];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(approved) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/leave/management');
  await expect(page.getByRole('heading', { name: 'Leave Management' })).toBeVisible();
  await expect(page.getByText('Family trip')).toBeVisible();

  await page.getByRole('button', { name: 'Review' }).click();
  await expect(page.getByRole('heading', { name: 'Review leave request' })).toBeVisible();
  await page.getByRole('button', { name: 'Approve', exact: true }).click();

  await expect(page.getByRole('heading', { name: 'Review leave request' })).toHaveCount(0);
  // The queue is still filtered to "Pending approval" — an approved request drops off it.
  await expect(page.getByText('No leave requests in this status.')).toBeVisible();
});

test('organization_administrator can revoke an approved leave request', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const approved = buildLeaveRequestRow({ status: 'approved', decided_by: 'someone', decided_at: '2026-09-05T00:00:00Z' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    leaveTypes: [buildLeaveTypeRow()],
    leaveRequests: [approved],
    affectedShifts: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'revoke_leave_request') {
        const revoked = { ...approved, status: 'revoked', decision_notes: payload.p_decision_notes ?? null };
        state.leaveRequests = [revoked];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(revoked) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/leave/management');
  await page.getByRole('button', { name: /pending approval/i }).click();
  await page.getByRole('button', { name: /approved/i }).click();
  await expect(page.getByText('Family trip')).toBeVisible();

  await page.getByRole('button', { name: 'Review' }).click();
  await page.getByRole('button', { name: 'Revoke', exact: true }).click();

  await expect(page.getByRole('heading', { name: 'Review leave request' })).toHaveCount(0);
  await expect(page.getByText('No leave requests in this status.')).toBeVisible();
});

test('an employee is blocked from the Leave Management approval queue', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/leave/management');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('an employee is blocked from Leave Configuration', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/leave/configuration');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('site_manager sees Team Leave read-only, with no approval controls', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'site_manager' }),
    leaveTypes: [buildLeaveTypeRow()],
    leaveRequests: [buildLeaveRequestRow({ status: 'approved' })],
  });

  await page.goto('/leave/team');
  await expect(page.getByRole('heading', { name: 'Team Leave' })).toBeVisible();
  await expect(page.getByText('Approved')).toBeVisible();
  // Field-level privacy: the summary projection never carries `reason`, so
  // it must not render here even though the same text appears in other
  // tests' full-projection views.
  await expect(page.getByText('Family trip')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Review' })).toHaveCount(0);
});

test('Team Leave has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'site_manager' }),
    leaveRequests: [buildLeaveRequestRow({ status: 'approved' })],
  });
  await page.goto('/leave/team');
  await expect(page.getByRole('heading', { name: 'Team Leave' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('My Leave has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    leaveRequests: [buildLeaveRequestRow()],
  });
  await page.goto('/leave');
  await expect(page.getByRole('heading', { name: 'My Leave' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Leave Management has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    leaveRequests: [buildLeaveRequestRow()],
  });
  await page.goto('/leave/management');
  await expect(page.getByRole('heading', { name: 'Leave Management' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Leave Configuration has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }) });
  await page.goto('/leave/configuration');
  await expect(page.getByRole('heading', { name: 'Leave Configuration' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
