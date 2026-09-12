import type { Page, Route } from '@playwright/test';

/**
 * Genuine Sebetsa REST/RPC mocking for the real table names Sebetsa's
 * services actually query (organizations, profiles, employees,
 * leave_types, leave_requests, leave_balances, notifications) — distinct
 * from mockData.ts, which mocks Funda360 table names (schools, learners)
 * that don't exist in this app. Every REST/RPC path this app can call
 * during a test is handled explicitly with a safe default; nothing falls
 * through to `route.continue()`, so a test can never accidentally reach
 * the real hosted Sebetsa project even though the prebuilt bundle is
 * compiled with the real VITE_SUPABASE_URL from .env.local.
 */

export const SEBETSA_TENANT_ID = '22222222-2222-2222-2222-222222222222';
export const SEBETSA_USER_ID = '11111111-1111-1111-1111-111111111111';

export async function fulfillJson(route: Route, body: unknown, status = 200) {
  await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
}

export function buildOrganizationRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: SEBETSA_TENANT_ID,
    name: 'Auris Demo Org',
    registration_number: null,
    industry: null,
    email: null,
    phone: null,
    website: null,
    logo_url: null,
    address: null,
    timezone: 'Africa/Johannesburg',
    currency: 'ZAR',
    language: 'en',
    status: 'active',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export function buildProfileRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: SEBETSA_USER_ID,
    tenant_id: SEBETSA_TENANT_ID,
    first_name: 'Test',
    last_name: 'User',
    email: 'test.user@sebetsa.example',
    phone: null,
    avatar_url: null,
    role: 'employee',
    status: 'active',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export function buildEmployeeRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'employee-1',
    tenant_id: SEBETSA_TENANT_ID,
    profile_id: SEBETSA_USER_ID,
    employee_number: 'EMP-0001',
    first_name: 'Test',
    last_name: 'Employee',
    email: null,
    phone: null,
    department_id: null,
    position_id: null,
    supervisor_id: null,
    region_id: null,
    home_site_id: null,
    employment_type: 'full_time',
    employment_status: 'active',
    employment_start_date: '2026-01-01',
    employment_end_date: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export function buildLeaveTypeRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'leave-type-annual',
    tenant_id: SEBETSA_TENANT_ID,
    name: 'Annual',
    is_paid: true,
    requires_documentation: false,
    default_annual_days: 15,
    status: 'active',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export function buildLeaveRequestRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'leave-request-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    leave_type_id: 'leave-type-annual',
    start_date: '2026-09-20',
    end_date: '2026-09-22',
    is_half_day: false,
    half_day_period: null,
    reason: 'Family trip',
    status: 'pending',
    decided_by: null,
    decided_at: null,
    decision_notes: null,
    supporting_document_ref: null,
    cancelled_at: null,
    cancelled_by: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    ...overrides,
  };
}

export function buildLeaveBalanceRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'leave-balance-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    leave_type_id: 'leave-type-annual',
    period_year: new Date().getFullYear(),
    opening_balance: 15,
    accrued: 0,
    used: 0,
    pending: 0,
    adjustment: 0,
    carried_over: 0,
    remaining: 15,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export interface SebetsaMockState {
  organization?: ReturnType<typeof buildOrganizationRow> | null;
  profile?: ReturnType<typeof buildProfileRow> | null;
  employee?: ReturnType<typeof buildEmployeeRow> | null;
  leaveTypes?: ReturnType<typeof buildLeaveTypeRow>[];
  leaveRequests?: ReturnType<typeof buildLeaveRequestRow>[];
  leaveBalances?: ReturnType<typeof buildLeaveBalanceRow>[];
  affectedShifts?: unknown[];
  notifications?: unknown[];
  /** Called for any `rpc/<fnName>` POST not covered by the generic table handlers above — return true if handled. */
  onRpc?: (fnName: string, payload: Record<string, unknown>, route: Route) => Promise<boolean>;
}

/**
 * Installs one comprehensive REST/RPC interceptor for everything the app
 * can request post-login. Call once per test, before page.goto(). Mutate
 * the returned `state` object's arrays (e.g. push a newly "created" leave
 * request) between actions to simulate server-side effects for subsequent
 * GETs within the same test.
 */
export async function installSebetsaMocks(page: Page, initial: SebetsaMockState = {}): Promise<SebetsaMockState> {
  const state: SebetsaMockState = {
    organization: buildOrganizationRow(),
    profile: buildProfileRow(),
    employee: buildEmployeeRow(),
    leaveTypes: [buildLeaveTypeRow()],
    leaveRequests: [],
    leaveBalances: [buildLeaveBalanceRow()],
    affectedShifts: [],
    notifications: [],
    ...initial,
  };

  // Belt-and-suspenders: any GoTrue call this app makes outside the
  // session-local paths AuthProvider/mfaService already avoid (see their
  // own comments) gets a harmless 200 rather than reaching real auth.
  await page.route('**/auth/v1/**', async (route: Route) => {
    await fulfillJson(route, {});
  });

  await page.route('**/rest/v1/**', async (route: Route) => {
    const url = new URL(route.request().url());
    const method = route.request().method();
    const path = url.pathname;

    if (path.endsWith('/organizations')) {
      return fulfillJson(route, state.organization ?? null);
    }

    if (path.endsWith('/profiles')) {
      return fulfillJson(route, state.profile ?? null);
    }

    if (path.endsWith('/employees')) {
      return fulfillJson(route, state.employee ?? null);
    }

    if (path.endsWith('/leave_types')) {
      return fulfillJson(route, state.leaveTypes ?? []);
    }

    if (path.endsWith('/leave_requests')) {
      // Actually honour the status/employee_id filters supabase-js sends
      // (?status=eq.X, ?employee_id=eq.X) — a mock that always returns
      // every row regardless of filter would make the filter UI (and any
      // test asserting a status transition removes a row from a filtered
      // view) meaningless.
      let rows = state.leaveRequests ?? [];
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) {
        const wanted = statusFilter.slice(3);
        rows = rows.filter((row) => (row as { status: string }).status === wanted);
      }
      const employeeFilter = url.searchParams.get('employee_id');
      if (employeeFilter?.startsWith('eq.')) {
        const wanted = employeeFilter.slice(3);
        rows = rows.filter((row) => (row as { employee_id: string }).employee_id === wanted);
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/leave_balances')) {
      return fulfillJson(route, state.leaveBalances ?? []);
    }

    if (path.endsWith('/leave_balance_transactions')) {
      return fulfillJson(route, []);
    }

    if (path.endsWith('/notifications')) {
      return fulfillJson(route, state.notifications ?? []);
    }

    if (path.includes('/rpc/')) {
      const fnName = path.split('/rpc/')[1] ?? '';
      let payload: Record<string, unknown> = {};
      try {
        payload = JSON.parse(route.request().postData() ?? '{}');
      } catch {
        payload = {};
      }

      if (fnName === 'get_leave_affected_shifts') {
        return fulfillJson(route, state.affectedShifts ?? []);
      }

      if (state.onRpc && (await state.onRpc(fnName, payload, route))) {
        return;
      }

      // No handler registered for this RPC in this test — fail loudly with
      // a 500 rather than silently succeeding, so an un-mocked call is
      // caught by the test instead of producing a misleading "it worked".
      return fulfillJson(route, { message: `unmocked rpc: ${fnName}`, code: 'P0001' }, 500);
    }

    // Never reach the real hosted project — every unrecognized read
    // defaults to an empty result rather than a network passthrough.
    if (method === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  return state;
}
