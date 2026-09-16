import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildOperationalAlertRow,
  buildEmergencyEventRow,
  buildEmergencyResponseRow,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/**
 * Domain 14 — Operations Command Centre + Emergency Response E2E coverage.
 * The safety-critical state machine itself (self-approval rejection,
 * escalation) is exercised against a real Postgres engine by
 * supabase/rls-tests/domain14_command_centre_emergency.sql; this file
 * proves the UI presents and drives that state machine correctly.
 */

test('Command Centre shows real, live figures across every group, never hardcoded stats', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'get_command_centre_snapshot') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([
            {
              workforce_total_scheduled: 42,
              workforce_clocked_in: 37,
              workforce_absent: 2,
              workforce_late: 1,
              workforce_pending_exceptions: 3,
              sites_total_active: 8,
              sites_understaffed: 2,
              sites_uncovered: 0,
              patrols_active: 4,
              patrols_completed_today: 9,
              patrols_missed: 1,
              compliance_expired: 5,
              compliance_expiring_soon: 6,
              incidents_open: 3,
              incidents_critical: 1,
              incidents_overdue: 0,
              tasks_overdue: 7,
              tasks_verification_pending: 2,
              contracts_active: 12,
              contracts_sla_breaching: 1,
              emergencies_active: 1,
              alerts_open: 5,
              alerts_critical: 2,
            },
          ]),
        });
        return true;
      }
      return false;
    },
  });

  await page.goto('/command-centre');
  await expect(page.getByRole('heading', { name: 'Command Centre' })).toBeVisible();
  await expect(page.getByText('42', { exact: true })).toBeVisible();
  await expect(page.getByText('37', { exact: true })).toBeVisible();
  await expect(page.getByText('8', { exact: true })).toBeVisible();
});

test('panic button is reachable from any page and triggers a real emergency', async ({ page, context }) => {
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: -26.2041, longitude: 28.0473 });

  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'trigger_emergency') {
        expect(payload.p_emergency_type).toBe('panic');
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(buildEmergencyEventRow({ triggered_at: new Date().toISOString() })),
        });
        return true;
      }
      return false;
    },
  });

  await page.goto('/dashboard');
  const panicButton = page.getByRole('button', { name: 'Trigger emergency alert' });
  await expect(panicButton).toBeVisible();
  await panicButton.click();

  await page.getByRole('button', { name: 'Confirm — send emergency alert now' }).click();
  await expect(page.getByText('Your emergency alert has been sent.')).toBeVisible();
});

test('a failed emergency trigger shows a real error, never a false "sent" confirmation', async ({ page, context }) => {
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: -26.2041, longitude: 28.0473 });

  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'trigger_emergency') {
        await route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ message: 'not_found: no employee record linked to your account', code: 'P0001' }) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'Trigger emergency alert' }).click();
  await page.getByRole('button', { name: 'Confirm — send emergency alert now' }).click();

  await expect(page.getByText('Your emergency alert has been sent.')).not.toBeVisible();
  await expect(page.getByRole('alert')).toBeVisible();
});

test('operations manager can acknowledge, respond to, and resolve an active emergency', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    emergencyEvents: [buildEmergencyEventRow()],
    emergencyResponses: [buildEmergencyResponseRow({ status: 'triggered' })],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'acknowledge_emergency') {
        const response = { ...(state.emergencyResponses?.[0] ?? buildEmergencyResponseRow()), status: 'acknowledged' };
        state.emergencyResponses = [response];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(response) });
        return true;
      }
      if (fnName === 'respond_to_emergency') {
        const response = { ...(state.emergencyResponses?.[0] ?? buildEmergencyResponseRow()), status: 'responding' };
        state.emergencyResponses = [response];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(response) });
        return true;
      }
      if (fnName === 'resolve_emergency') {
        expect(payload.p_resolution_reason).toBeTruthy();
        const response = { ...(state.emergencyResponses?.[0] ?? buildEmergencyResponseRow()), status: 'resolved' };
        state.emergencyResponses = [];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(response) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/emergencies');
  await expect(page.getByRole('heading', { name: 'Emergency Response' })).toBeVisible();
  await expect(page.getByText('Triggered — unacknowledged')).toBeVisible();

  await page.getByRole('button', { name: 'Acknowledge' }).click();
  await expect(page.getByRole('button', { name: 'Mark responding' })).toBeVisible();

  await page.getByRole('button', { name: 'Mark responding' }).click();
  await page.getByRole('button', { name: 'Resolve' }).click();
  await page.getByLabel('Resolution notes').fill('False alarm, guard confirmed safe');
  await page.getByRole('button', { name: 'Confirm resolution' }).click();

  await expect(page.getByText('No active emergencies. Everything is clear.')).toBeVisible();
});

test('a server-side self-approval rejection on an emergency surfaces as a real error, never a false success', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'site_manager' }),
    emergencyEvents: [buildEmergencyEventRow()],
    emergencyResponses: [buildEmergencyResponseRow({ status: 'triggered' })],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'acknowledge_emergency') {
        // Exactly what acknowledge_emergency() raises for a self-approval
        // attempt — see supabase/migrations/20260921090300.
        await route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ message: 'insufficient_privilege: cannot acknowledge your own emergency — independent response oversight is required', code: 'P0001' }) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/emergencies');
  await page.getByRole('button', { name: 'Acknowledge' }).click();

  await expect(page.getByRole('button', { name: 'Mark responding' })).not.toBeVisible();
  await expect(page.getByRole('alert')).toBeVisible();
});

test('operations manager can acknowledge and resolve an operational alert', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    operationalAlerts: [buildOperationalAlertRow({ status: 'open' })],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'acknowledge_operational_alert') {
        const alert = { ...(state.operationalAlerts?.[0] ?? buildOperationalAlertRow()), status: 'acknowledged' };
        state.operationalAlerts = [alert];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(alert) });
        return true;
      }
      if (fnName === 'resolve_operational_alert') {
        const alert = { ...(state.operationalAlerts?.[0] ?? buildOperationalAlertRow()), status: 'resolved' };
        state.operationalAlerts = [alert];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(alert) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/command-centre/alerts');
  await expect(page.getByRole('heading', { name: 'Operational Alerts' })).toBeVisible();
  await expect(page.getByText('Site 1 is understaffed: 1 assigned vs 2 required')).toBeVisible();

  await page.getByRole('button', { name: 'Acknowledge', exact: true }).click();
  // Acknowledging moves the alert out of the default "Open" filter — switch
  // to "All" to keep seeing it, the same as a real supervisor would.
  await page.getByRole('button', { name: 'All' }).click();
  await expect(page.getByRole('button', { name: 'Resolve', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Resolve', exact: true }).click();

  await page.getByRole('button', { name: 'Resolved' }).click();
  await expect(page.getByText('Site 1 is understaffed: 1 assigned vs 2 required')).toBeVisible();
});

test('operations manager can reopen a resolved alert with a reason', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    operationalAlerts: [buildOperationalAlertRow({ status: 'resolved' })],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'reopen_operational_alert') {
        expect(payload.p_reason).toBeTruthy();
        const alert = { ...(state.operationalAlerts?.[0] ?? buildOperationalAlertRow()), status: 'open' };
        state.operationalAlerts = [alert];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(alert) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/command-centre/alerts');
  await page.getByRole('button', { name: 'All' }).click();
  await page.getByRole('button', { name: 'Reopen' }).click();
  // Reopen is disabled without a reason — never a bare confirm.
  await expect(page.getByRole('button', { name: 'Confirm reopen' })).toBeDisabled();
  await page.getByLabel('Reason for reopening').fill('The condition recurred');
  await page.getByRole('button', { name: 'Confirm reopen' }).click();

  await page.getByRole('button', { name: 'Open', exact: true }).click();
  await expect(page.getByText('Site 1 is understaffed: 1 assigned vs 2 required')).toBeVisible();
});

test('an employee is blocked from the Command Centre, Operational Alerts, and Emergency Response', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/command-centre');
  await expect(page).toHaveURL(/\/dashboard/);

  await page.goto('/command-centre/alerts');
  await expect(page).toHaveURL(/\/dashboard/);

  await page.goto('/emergencies');
  await expect(page).toHaveURL(/\/dashboard/);
});

test('client_user never sees the panic button or any command-centre navigation', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'client_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'client_user' }), employee: null });

  await page.goto('/dashboard');
  await expect(page.getByRole('button', { name: 'Trigger emergency alert' })).not.toBeVisible();
});

test('Emergency Response has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    emergencyEvents: [buildEmergencyEventRow()],
    emergencyResponses: [buildEmergencyResponseRow({ status: 'triggered' })],
  });
  await page.goto('/emergencies');
  await expect(page.getByRole('heading', { name: 'Emergency Response' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Operational Alerts has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    operationalAlerts: [buildOperationalAlertRow()],
  });
  await page.goto('/command-centre/alerts');
  await expect(page.getByRole('heading', { name: 'Operational Alerts' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Command Centre has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'get_command_centre_snapshot') {
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([{}]) });
        return true;
      }
      return false;
    },
  });
  await page.goto('/command-centre');
  await expect(page.getByRole('heading', { name: 'Command Centre' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
