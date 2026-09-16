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

export function buildShiftRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  const now = new Date();
  const start = new Date(now);
  start.setHours(8, 0, 0, 0);
  const end = new Date(now);
  end.setHours(17, 0, 0, 0);
  return {
    id: 'shift-1',
    tenant_id: SEBETSA_TENANT_ID,
    site_id: 'site-1',
    employee_id: 'employee-1',
    supervisor_id: null,
    shift_definition_id: null,
    starts_at: start.toISOString(),
    ends_at: end.toISOString(),
    status: 'scheduled',
    notes: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

export function buildAttendanceRecordRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'attendance-1',
    tenant_id: SEBETSA_TENANT_ID,
    shift_id: 'shift-1',
    site_id: 'site-1',
    employee_id: 'employee-1',
    status: 'unconfirmed',
    clock_in_at: null,
    clock_out_at: null,
    late_minutes: null,
    early_departure_minutes: null,
    worked_minutes: null,
    overtime_minutes: null,
    recorded_by: null,
    notes: null,
    gps_verification_status: 'not_applicable',
    created_at: '2026-09-12T08:00:00Z',
    updated_at: '2026-09-12T08:00:00Z',
    ...overrides,
  };
}

export function buildAttendanceCorrectionRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'correction-1',
    tenant_id: SEBETSA_TENANT_ID,
    attendance_record_id: 'attendance-1',
    field: 'clock_in_at',
    previous_value: '2026-09-12T08:15:00Z',
    new_value: '2026-09-12T08:00:00Z',
    reason: 'Forgot to clock in on time',
    status: 'pending',
    requested_by: SEBETSA_USER_ID,
    reviewed_by: null,
    reviewed_at: null,
    review_notes: null,
    created_at: '2026-09-12T08:20:00Z',
    updated_at: '2026-09-12T08:20:00Z',
    ...overrides,
  };
}

export function buildTaskRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'task-1',
    tenant_id: SEBETSA_TENANT_ID,
    site_id: 'site-1',
    assignee_id: 'employee-1',
    team_id: null,
    supervisor_id: null,
    title: 'Inspect fire extinguishers',
    description: 'Check pressure and expiry on all site extinguishers.',
    priority: 'normal',
    status: 'open',
    due_at: null,
    completed_at: null,
    completed_by: null,
    requires_evidence: false,
    created_by: null,
    created_at: '2026-09-12T08:00:00Z',
    updated_at: '2026-09-12T08:00:00Z',
    ...overrides,
  };
}

export function buildTaskChecklistItemRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'checklist-1',
    tenant_id: SEBETSA_TENANT_ID,
    task_id: 'task-1',
    label: 'Check pressure gauges',
    sort_order: 1,
    is_completed: false,
    completed_by: null,
    completed_at: null,
    notes: null,
    created_at: '2026-09-12T08:00:00Z',
    ...overrides,
  };
}

export function buildEmployeeDocumentRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'document-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    document_type: 'certificate',
    file_name: 'first-aid.pdf',
    mime_type: 'application/pdf',
    file_size_bytes: 500000,
    storage_path: `${SEBETSA_TENANT_ID}/employee-1/document-1-first-aid.pdf`,
    version: 1,
    supersedes_document_id: null,
    status: 'uploaded',
    expiry_date: null,
    uploaded_by: SEBETSA_USER_ID,
    verified_by: null,
    verified_at: null,
    review_notes: null,
    created_at: '2026-09-12T08:00:00Z',
    updated_at: '2026-09-12T08:00:00Z',
    ...overrides,
  };
}

export function buildIncidentRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'incident-1',
    tenant_id: SEBETSA_TENANT_ID,
    reference_number: 'INC-2026-000001',
    site_id: null,
    contract_id: null,
    category: 'workplace_safety',
    severity: 'medium',
    status: 'reported',
    occurred_at: '2026-09-14T08:00:00Z',
    reported_by: SEBETSA_USER_ID,
    description: 'Slip near the loading bay entrance.',
    investigation_notes: null,
    corrective_action_summary: null,
    closed_by: null,
    closed_at: null,
    created_at: '2026-09-14T08:00:00Z',
    updated_at: '2026-09-14T08:00:00Z',
    ...overrides,
  };
}

export function buildIncidentActionRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'incident-action-1',
    tenant_id: SEBETSA_TENANT_ID,
    incident_id: 'incident-1',
    description: 'Place wet floor signage',
    owner_profile_id: SEBETSA_USER_ID,
    due_date: '2026-09-16',
    status: 'open',
    completed_at: null,
    verified_by: null,
    verified_at: null,
    created_at: '2026-09-14T08:05:00Z',
    updated_at: '2026-09-14T08:05:00Z',
    ...overrides,
  };
}

export function buildAssetRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'asset-1',
    tenant_id: SEBETSA_TENANT_ID,
    asset_number: 'AST-001',
    name: 'Floor Buffer',
    category: 'equipment',
    serial_number: null,
    site_id: 'site-1',
    custodian_employee_id: null,
    status: 'available',
    condition: 'good',
    acquisition_date: null,
    acquisition_cost: null,
    notes: null,
    created_at: '2026-09-15T08:00:00Z',
    updated_at: '2026-09-15T08:00:00Z',
    ...overrides,
  };
}

export function buildInventoryItemRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'item-1',
    tenant_id: SEBETSA_TENANT_ID,
    sku: 'SKU-001',
    name: 'Disinfectant 5L',
    category: 'consumables',
    unit: 'each',
    reorder_threshold: 5,
    is_active: true,
    created_at: '2026-09-15T08:00:00Z',
    updated_at: '2026-09-15T08:00:00Z',
    ...overrides,
  };
}

export function buildProcurementRequestRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'proc-1',
    tenant_id: SEBETSA_TENANT_ID,
    requested_by: SEBETSA_USER_ID,
    site_id: null,
    item_description: 'Replacement mop heads',
    quantity: 10,
    estimated_cost: 150,
    status: 'submitted',
    approved_by: null,
    approved_at: null,
    rejected_reason: null,
    created_at: '2026-09-15T08:00:00Z',
    updated_at: '2026-09-15T08:00:00Z',
    ...overrides,
  };
}

export function buildSkillRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return { id: 'skill-1', tenant_id: SEBETSA_TENANT_ID, name: 'First Aid', category: 'safety', created_at: '2026-09-17T08:00:00Z', updated_at: '2026-09-17T08:00:00Z', ...overrides };
}

export function buildEmployeeSkillRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'employee-skill-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    skill_id: 'skill-1',
    proficiency_level: 'intermediate',
    evidence_document_id: null,
    verified_by: null,
    verified_at: null,
    created_at: '2026-09-17T08:00:00Z',
    updated_at: '2026-09-17T08:00:00Z',
    ...overrides,
  };
}

export function buildPerformanceReviewRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'review-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    reviewer_profile_id: SEBETSA_USER_ID,
    review_period_start: '2026-01-01',
    review_period_end: '2026-06-30',
    status: 'employee_review',
    overall_rating: 4,
    manager_comments: 'Solid performance this period.',
    employee_comments: null,
    finalized_at: null,
    created_at: '2026-09-17T08:00:00Z',
    updated_at: '2026-09-17T08:00:00Z',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Domain 13/14/15 — GPS field presence/guard tours, command centre/
// emergency response, workforce intelligence + AI. Same real-table-name,
// real-shape mocking convention as everything above.

export function buildPatrolRouteRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'route-1',
    tenant_id: SEBETSA_TENANT_ID,
    site_id: 'site-1',
    name: 'Night Patrol',
    expected_duration_minutes: 30,
    allowed_start_window_minutes: 60,
    completion_threshold_pct: 100,
    active: true,
    created_at: '2026-09-14T08:00:00Z',
    updated_at: '2026-09-14T08:00:00Z',
    ...overrides,
  };
}

export function buildPatrolRunRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'run-1',
    tenant_id: SEBETSA_TENANT_ID,
    patrol_route_id: 'route-1',
    site_id: 'site-1',
    employee_id: 'employee-1',
    status: 'in_progress',
    started_at: new Date().toISOString(),
    completed_at: null,
    expected_checkpoint_count: 2,
    scanned_checkpoint_count: 0,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

export function buildPatrolCheckpointScanRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'scan-1',
    tenant_id: SEBETSA_TENANT_ID,
    patrol_run_id: 'run-1',
    checkpoint_id: 'checkpoint-1',
    scanned_code: 'CP-A',
    employee_id: 'employee-1',
    sequence_number: 1,
    scanned_at: new Date().toISOString(),
    scan_method: 'manual',
    latitude: null,
    longitude: null,
    verification_result: 'valid',
    risk_flags: [],
    ...overrides,
  };
}

export function buildOperationalAlertRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'alert-1',
    tenant_id: SEBETSA_TENANT_ID,
    alert_type: 'site_understaffed',
    severity: 'warning',
    site_id: 'site-1',
    employee_id: null,
    contract_id: null,
    message: 'Site 1 is understaffed: 1 assigned vs 2 required',
    status: 'open',
    acknowledged_by: null,
    acknowledged_at: null,
    resolved_by: null,
    resolved_at: null,
    resolution_notes: null,
    created_at: '2026-09-14T08:00:00Z',
    updated_at: '2026-09-14T08:00:00Z',
    ...overrides,
  };
}

export function buildEmergencyEventRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'emergency-1',
    tenant_id: SEBETSA_TENANT_ID,
    employee_id: 'employee-1',
    site_id: 'site-1',
    shift_id: null,
    emergency_type: 'panic',
    latitude: -26.2041,
    longitude: 28.0473,
    accuracy_meters: 15,
    triggered_at: new Date().toISOString(),
    device_context: {},
    ...overrides,
  };
}

export function buildEmergencyResponseRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'emergency-response-1',
    tenant_id: SEBETSA_TENANT_ID,
    emergency_event_id: 'emergency-1',
    status: 'triggered',
    acknowledged_by: null,
    acknowledged_at: null,
    responding_by: null,
    responding_at: null,
    resolved_by: null,
    resolved_at: null,
    resolution_reason: null,
    escalation_level: 0,
    last_escalated_at: null,
    notes: null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...overrides,
  };
}

export function buildAiQueryLogRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'ai-log-1',
    tenant_id: SEBETSA_TENANT_ID,
    actor_profile_id: SEBETSA_USER_ID,
    query_text: 'Which sites are understaffed?',
    matched_intent: 'understaffed_sites',
    tool_calls: [{ tool: 'understaffed_sites' }],
    response_text: 'Site 1 is understaffed.',
    insight_kind: 'rule_based',
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

export function buildShiftRecommendationRow(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id: 'recommendation-1',
    tenant_id: SEBETSA_TENANT_ID,
    site_id: 'site-1',
    shift_date: '2026-09-20',
    starts_at: '2026-09-20T08:00:00Z',
    ends_at: '2026-09-20T16:00:00Z',
    candidate_employee_id: 'employee-1',
    score: 92.5,
    reasons: [{ factor: 'assigned_to_site', detail: 'currently has an active site assignment here' }],
    status: 'suggested',
    generated_at: new Date().toISOString(),
    decided_by: null,
    decided_at: null,
    published_shift_id: null,
    ...overrides,
  };
}

/** Mocks a Storage upload (POST .../storage/v1/object/{bucket}/{path}) — storage-js expects {Id, Key} back. */
export async function installStorageUploadMock(page: Page, bucket: string) {
  await page.route(`**/storage/v1/object/${bucket}/**`, async (route: Route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    await fulfillJson(route, { Id: 'mock-object-id', Key: `${bucket}/mock-path` });
  });
}

/** Mocks a Storage signed-URL request (POST .../storage/v1/object/sign/{bucket}/{path}). */
export async function installStorageSignedUrlMock(page: Page, bucket: string) {
  await page.route(`**/storage/v1/object/sign/${bucket}/**`, async (route: Route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    await fulfillJson(route, { signedURL: `/object/sign/${bucket}/mock-path?token=mock-token` });
  });
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
  shifts?: ReturnType<typeof buildShiftRow>[];
  attendanceRecords?: ReturnType<typeof buildAttendanceRecordRow>[];
  attendanceBreaks?: Record<string, unknown>[];
  attendanceCorrections?: ReturnType<typeof buildAttendanceCorrectionRow>[];
  tasks?: ReturnType<typeof buildTaskRow>[];
  taskChecklistItems?: ReturnType<typeof buildTaskChecklistItemRow>[];
  taskEvidence?: Record<string, unknown>[];
  employeeDocuments?: ReturnType<typeof buildEmployeeDocumentRow>[];
  incidents?: ReturnType<typeof buildIncidentRow>[];
  incidentActions?: ReturnType<typeof buildIncidentActionRow>[];
  assets?: ReturnType<typeof buildAssetRow>[];
  inventoryItems?: ReturnType<typeof buildInventoryItemRow>[];
  procurementRequests?: ReturnType<typeof buildProcurementRequestRow>[];
  employeeSkills?: ReturnType<typeof buildEmployeeSkillRow>[];
  qualifications?: Record<string, unknown>[];
  trainingEnrollments?: Record<string, unknown>[];
  performanceReviews?: ReturnType<typeof buildPerformanceReviewRow>[];
  developmentActions?: Record<string, unknown>[];
  patrolRoutes?: ReturnType<typeof buildPatrolRouteRow>[];
  patrolRuns?: ReturnType<typeof buildPatrolRunRow>[];
  patrolCheckpointScans?: ReturnType<typeof buildPatrolCheckpointScanRow>[];
  operationalAlerts?: ReturnType<typeof buildOperationalAlertRow>[];
  emergencyEvents?: ReturnType<typeof buildEmergencyEventRow>[];
  emergencyResponses?: ReturnType<typeof buildEmergencyResponseRow>[];
  aiQueryLog?: ReturnType<typeof buildAiQueryLogRow>[];
  shiftRecommendations?: ReturnType<typeof buildShiftRecommendationRow>[];
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
    shifts: [],
    attendanceRecords: [],
    attendanceBreaks: [],
    attendanceCorrections: [],
    tasks: [],
    taskChecklistItems: [],
    taskEvidence: [],
    employeeDocuments: [],
    incidents: [],
    incidentActions: [],
    assets: [],
    inventoryItems: [],
    procurementRequests: [],
    employeeSkills: [],
    qualifications: [],
    trainingEnrollments: [],
    performanceReviews: [],
    developmentActions: [],
    patrolRoutes: [],
    patrolRuns: [],
    patrolCheckpointScans: [],
    operationalAlerts: [],
    emergencyEvents: [],
    emergencyResponses: [],
    aiQueryLog: [],
    shiftRecommendations: [],
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

    if (path.endsWith('/shifts')) {
      return fulfillJson(route, state.shifts ?? []);
    }

    if (path.endsWith('/attendance_records')) {
      let rows = state.attendanceRecords ?? [];
      const employeeFilter = url.searchParams.get('employee_id');
      if (employeeFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { employee_id: string }).employee_id === employeeFilter.slice(3));
      }
      const clockOutIsNull = url.searchParams.get('clock_out_at') === 'is.null';
      if (clockOutIsNull) {
        rows = rows.filter((row) => (row as { clock_out_at: string | null }).clock_out_at === null);
      }
      // .maybeSingle() callers (getOpenAttendanceForEmployee) expect a
      // single object or null, not an array — mirror PostgREST's
      // Accept: single-object header behavior used by supabase-js.
      if (route.request().headers()['accept']?.includes('vnd.pgrst.object')) {
        return fulfillJson(route, rows[0] ?? null);
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/attendance_breaks')) {
      let rows = state.attendanceBreaks ?? [];
      const attendanceIdFilter = url.searchParams.get('attendance_record_id');
      if (attendanceIdFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { attendance_record_id: string }).attendance_record_id === attendanceIdFilter.slice(3));
      }
      const breakEndIsNull = url.searchParams.get('break_end') === 'is.null';
      if (breakEndIsNull) {
        rows = rows.filter((row) => (row as { break_end: string | null }).break_end === null);
      }
      if (route.request().headers()['accept']?.includes('vnd.pgrst.object')) {
        return fulfillJson(route, rows[0] ?? null);
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/attendance_corrections')) {
      let rows = state.attendanceCorrections ?? [];
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { status: string }).status === statusFilter.slice(3));
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/attendance_policies')) {
      return fulfillJson(route, null);
    }

    if (path.endsWith('/tasks')) {
      let rows = state.tasks ?? [];
      const assigneeFilter = url.searchParams.get('assignee_id');
      if (assigneeFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { assignee_id: string }).assignee_id === assigneeFilter.slice(3));
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/task_checklist_items')) {
      const rows = state.taskChecklistItems ?? [];
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/task_evidence')) {
      if (method === 'POST') {
        let payload: Record<string, unknown> = {};
        try {
          payload = JSON.parse(route.request().postData() ?? '{}');
        } catch {
          payload = {};
        }
        const created = { id: `evidence-${(state.taskEvidence?.length ?? 0) + 1}`, tenant_id: SEBETSA_TENANT_ID, submitted_by: SEBETSA_USER_ID, created_at: new Date().toISOString(), ...payload };
        state.taskEvidence = [created, ...(state.taskEvidence ?? [])];
        return fulfillJson(route, created);
      }
      return fulfillJson(route, state.taskEvidence ?? []);
    }

    if (path.endsWith('/employee_documents')) {
      let rows = state.employeeDocuments ?? [];
      const employeeFilter = url.searchParams.get('employee_id');
      if (employeeFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { employee_id: string }).employee_id === employeeFilter.slice(3));
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/notifications')) {
      return fulfillJson(route, state.notifications ?? []);
    }

    if (path.endsWith('/incidents')) {
      let rows = state.incidents ?? [];
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { status: string }).status === statusFilter.slice(3));
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/incident_actions')) {
      let rows = state.incidentActions ?? [];
      const incidentFilter = url.searchParams.get('incident_id');
      if (incidentFilter?.startsWith('eq.')) {
        rows = rows.filter((row) => (row as { incident_id: string }).incident_id === incidentFilter.slice(3));
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/incident_affected_employees')) {
      return fulfillJson(route, []);
    }

    if (path.endsWith('/compliance_requirements')) {
      return fulfillJson(route, []);
    }

    if (path.endsWith('/compliance_records')) {
      return fulfillJson(route, []);
    }

    if (path.endsWith('/assets')) {
      return fulfillJson(route, state.assets ?? []);
    }

    if (path.endsWith('/inventory_items')) {
      return fulfillJson(route, state.inventoryItems ?? []);
    }

    if (path.endsWith('/inventory_movements')) {
      return fulfillJson(route, []);
    }

    if (path.endsWith('/procurement_requests')) {
      return fulfillJson(route, state.procurementRequests ?? []);
    }

    if (path.endsWith('/skills')) return fulfillJson(route, []);
    if (path.endsWith('/employee_skills')) return fulfillJson(route, state.employeeSkills ?? []);
    if (path.endsWith('/employee_qualifications')) return fulfillJson(route, state.qualifications ?? []);
    if (path.endsWith('/training_programs')) return fulfillJson(route, []);
    if (path.endsWith('/training_enrollments')) return fulfillJson(route, state.trainingEnrollments ?? []);
    if (path.endsWith('/performance_reviews')) return fulfillJson(route, state.performanceReviews ?? []);
    if (path.endsWith('/development_actions')) return fulfillJson(route, state.developmentActions ?? []);

    if (path.endsWith('/patrol_routes')) {
      let rows = state.patrolRoutes ?? [];
      const siteFilter = url.searchParams.get('site_id');
      if (siteFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { site_id: string }).site_id === siteFilter.slice(3));
      const activeFilter = url.searchParams.get('active');
      if (activeFilter === 'eq.true') rows = rows.filter((row) => (row as { active: boolean }).active === true);
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/patrol_runs')) {
      let rows = state.patrolRuns ?? [];
      const employeeFilter = url.searchParams.get('employee_id');
      if (employeeFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { employee_id: string }).employee_id === employeeFilter.slice(3));
      const tenantFilter = url.searchParams.get('tenant_id');
      if (tenantFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { tenant_id: string }).tenant_id === tenantFilter.slice(3));
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { status: string }).status === statusFilter.slice(3));
      if (route.request().headers()['accept']?.includes('vnd.pgrst.object')) {
        return fulfillJson(route, rows[0] ?? null);
      }
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/patrol_checkpoint_scans')) {
      let rows = state.patrolCheckpointScans ?? [];
      const runFilter = url.searchParams.get('patrol_run_id');
      if (runFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { patrol_run_id: string }).patrol_run_id === runFilter.slice(3));
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/operational_alerts')) {
      let rows = state.operationalAlerts ?? [];
      const tenantFilter = url.searchParams.get('tenant_id');
      if (tenantFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { tenant_id: string }).tenant_id === tenantFilter.slice(3));
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { status: string }).status === statusFilter.slice(3));
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/emergency_events')) {
      let rows = state.emergencyEvents ?? [];
      const idFilter = url.searchParams.get('id');
      if (idFilter?.startsWith('in.')) {
        const ids = idFilter.slice(4, -1).split(',');
        rows = rows.filter((row) => ids.includes((row as { id: string }).id));
      }
      const tenantFilter = url.searchParams.get('tenant_id');
      if (tenantFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { tenant_id: string }).tenant_id === tenantFilter.slice(3));
      if (method === 'PATCH') return fulfillJson(route, {});
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/emergency_responses')) {
      let rows = state.emergencyResponses ?? [];
      const tenantFilter = url.searchParams.get('tenant_id');
      if (tenantFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { tenant_id: string }).tenant_id === tenantFilter.slice(3));
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('neq.')) rows = rows.filter((row) => (row as { status: string }).status !== statusFilter.slice(4));
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/ai_query_log')) {
      let rows = state.aiQueryLog ?? [];
      const actorFilter = url.searchParams.get('actor_profile_id');
      if (actorFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { actor_profile_id: string }).actor_profile_id === actorFilter.slice(3));
      return fulfillJson(route, rows);
    }

    if (path.endsWith('/shift_recommendations')) {
      let rows = state.shiftRecommendations ?? [];
      const tenantFilter = url.searchParams.get('tenant_id');
      if (tenantFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { tenant_id: string }).tenant_id === tenantFilter.slice(3));
      const statusFilter = url.searchParams.get('status');
      if (statusFilter?.startsWith('eq.')) rows = rows.filter((row) => (row as { status: string }).status === statusFilter.slice(3));
      return fulfillJson(route, rows);
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

/**
 * Mocks the paginated profiles list query UsersPage.tsx issues (`limit`/
 * `offset` params, needs a `content-range` header for the total count) —
 * distinct from installSebetsaMocks' own `/profiles` handler, which only
 * ever returns a single row (the signed-in caller's own profile).
 */
export async function installUsersListMock(page: Page, users: ReturnType<typeof buildProfileRow>[]) {
  await page.route('**/rest/v1/profiles*', async (route: Route) => {
    const url = new URL(route.request().url());
    const isListQuery = url.searchParams.has('limit') || url.searchParams.has('offset');
    if (!isListQuery) return route.fallback();

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: {
        'content-range': `0-${Math.max(users.length - 1, 0)}/${users.length}`,
        'access-control-expose-headers': 'content-range',
      },
      body: JSON.stringify(users),
    });
  });
}

/** Mocks a `.rpc('admin_create_user' | 'admin_update_user_role', ...)` call. */
export async function installRpcMock(
  page: Page,
  fnName: 'admin_create_user' | 'admin_update_user_role',
  handler: (route: Route) => Promise<void>,
) {
  await page.route(`**/rest/v1/rpc/${fnName}`, handler);
}
