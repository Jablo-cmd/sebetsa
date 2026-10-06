import type { Row, Session } from './fakeBackend';

/**
 * Sebetsa's single deterministic E2E dataset. Fictional people and
 * organisations only — no real data, no credentials.
 *
 *   organisation → region → client → contract → site → team → employee
 *   → shift → attendance → task/checklist/evidence → incident/corrective
 *   action → compliance → documents → assets/inventory/procurement
 *   → skills/training/performance → notifications
 *
 * Time is pinned: the browser clock is fixed to FIXED_NOW (see test.ts), so
 * "today", "this week" and "expires in 30 days" are stable on every run.
 */

/** Monday 21 Sep 2026, 08:00 in Africa/Johannesburg. */
export const FIXED_NOW = '2026-09-21T06:00:00.000Z';
export const TODAY = '2026-09-21';

export function dateOffset(days: number): string {
  const d = new Date(`${TODAY}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function uuid(kind: number, n: number): string {
  return `00000000-0000-4000-8000-${String(kind).padStart(4, '0')}${String(n).padStart(8, '0')}`;
}

export const ID = {
  org: uuid(1, 1),
  rivalOrg: uuid(1, 2),
  regionGauteng: uuid(2, 1),
  regionWesternCape: uuid(2, 2),
  clientHarbour: uuid(3, 1),
  clientNorthgate: uuid(3, 2),
  contractHarbour: uuid(4, 1),
  contractNorthgate: uuid(4, 2),
  siteTowerA: uuid(5, 1),
  siteAtrium: uuid(5, 2),
  siteFoodCourt: uuid(5, 3),
  deptCleaning: uuid(6, 1),
  deptHr: uuid(6, 2),
  posCleaner: uuid(7, 1),
  posSupervisor: uuid(7, 2),
  teamTowerADay: uuid(8, 1),
  shiftDefDay: uuid(9, 1),
  shiftDefNight: uuid(9, 2),
  leaveAnnual: uuid(10, 1),
  leaveSick: uuid(10, 2),
  leaveFamily: uuid(10, 3),
  taskWashrooms: uuid(11, 1),
  taskReception: uuid(11, 2),
  taskKitchen: uuid(11, 3),
  incidentSlip: uuid(12, 1),
  actionSignage: uuid(12, 2),
  reqCoida: uuid(13, 1),
  recordCoida: uuid(13, 2),
  docChemical: uuid(14, 1),
  docFirstAid: uuid(14, 2),
  assetScrubber: uuid(15, 1),
  assetVacuum: uuid(15, 2),
  itemCleaner: uuid(16, 1),
  itemMopHeads: uuid(16, 2),
  procMops: uuid(17, 1),
  skillChemical: uuid(18, 1),
  skillFirstAid: uuid(18, 2),
  programManualHandling: uuid(19, 1),
  reviewThabo: uuid(20, 1),
  rivalClient: uuid(3, 90),
  rivalSite: uuid(5, 90),
  rivalEmployee: uuid(21, 90),
  rivalProfile: uuid(22, 90),
} as const;

export type Persona = {
  role: string;
  profileId: string;
  employeeId: string | null;
  firstName: string;
  lastName: string;
  email: string;
  employeeNumber: string | null;
  departmentId: string | null;
  positionId: string | null;
};

const personaList: Persona[] = [
  { role: 'platform_administrator', profileId: uuid(22, 1), employeeId: null, firstName: 'Pat', lastName: 'Platform', email: 'pat.platform@sebetsa.example', employeeNumber: null, departmentId: null, positionId: null },
  { role: 'organization_administrator', profileId: uuid(22, 2), employeeId: uuid(21, 2), firstName: 'Olivia', lastName: 'Okafor', email: 'olivia.okafor@brightway.example', employeeNumber: 'BW-0002', departmentId: ID.deptHr, positionId: null },
  { role: 'operations_manager', profileId: uuid(22, 3), employeeId: uuid(21, 3), firstName: 'Omar', lastName: 'Mokoena', email: 'omar.mokoena@brightway.example', employeeNumber: 'BW-0003', departmentId: ID.deptCleaning, positionId: null },
  { role: 'regional_manager', profileId: uuid(22, 4), employeeId: uuid(21, 4), firstName: 'Rina', lastName: 'Naidoo', email: 'rina.naidoo@brightway.example', employeeNumber: 'BW-0004', departmentId: ID.deptCleaning, positionId: null },
  { role: 'site_manager', profileId: uuid(22, 5), employeeId: uuid(21, 5), firstName: 'Sipho', lastName: 'Dlamini', email: 'sipho.dlamini@brightway.example', employeeNumber: 'BW-0005', departmentId: ID.deptCleaning, positionId: ID.posSupervisor },
  { role: 'supervisor', profileId: uuid(22, 6), employeeId: uuid(21, 6), firstName: 'Sarah', lastName: 'van Wyk', email: 'sarah.vanwyk@brightway.example', employeeNumber: 'BW-0006', departmentId: ID.deptCleaning, positionId: ID.posSupervisor },
  { role: 'hr_user', profileId: uuid(22, 7), employeeId: uuid(21, 7), firstName: 'Hannah', lastName: 'Botha', email: 'hannah.botha@brightway.example', employeeNumber: 'BW-0007', departmentId: ID.deptHr, positionId: null },
  { role: 'employee', profileId: uuid(22, 8), employeeId: uuid(21, 8), firstName: 'Thabo', lastName: 'Nkosi', email: 'thabo.nkosi@brightway.example', employeeNumber: 'BW-0008', departmentId: ID.deptCleaning, positionId: ID.posCleaner },
  { role: 'employee_two', profileId: uuid(22, 9), employeeId: uuid(21, 9), firstName: 'Lerato', lastName: 'Mahlangu', email: 'lerato.mahlangu@brightway.example', employeeNumber: 'BW-0009', departmentId: ID.deptCleaning, positionId: ID.posCleaner },
  { role: 'client_user', profileId: uuid(22, 10), employeeId: null, firstName: 'Chris', lastName: 'Client', email: 'chris.client@harbourpoint.example', employeeNumber: null, departmentId: null, positionId: null },
];

export const PERSONAS: Record<string, Persona> = Object.fromEntries(personaList.map((p) => [p.role, p]));

/** Roles that can be signed in as (employee_two is a second `employee`). */
export type SignInAs =
  | 'platform_administrator'
  | 'organization_administrator'
  | 'operations_manager'
  | 'regional_manager'
  | 'site_manager'
  | 'supervisor'
  | 'hr_user'
  | 'employee'
  | 'employee_two'
  | 'client_user';

export function sessionFor(as: SignInAs): Session {
  const p = PERSONAS[as];
  return {
    userId: p.profileId,
    tenantId: as === 'platform_administrator' ? null : ID.org,
    role: as === 'employee_two' ? 'employee' : as,
    email: p.email,
  };
}

const created = '2026-01-05T08:00:00.000Z';

function ts(extra: Row): Row {
  return { created_at: created, updated_at: created, ...extra };
}

export function buildDataset(): Record<string, Row[]> {
  const T = ID.org;

  const profiles: Row[] = personaList.map((p) =>
    ts({
      id: p.profileId,
      tenant_id: p.role === 'platform_administrator' ? null : T,
      first_name: p.firstName,
      last_name: p.lastName,
      email: p.email,
      phone: null,
      avatar_url: null,
      role: p.role === 'employee_two' ? 'employee' : p.role,
      status: 'active',
    }),
  );
  profiles.push(
    ts({ id: ID.rivalProfile, tenant_id: ID.rivalOrg, first_name: 'Rhea', last_name: 'Rival', email: 'rhea.rival@rivalservices.example', phone: null, avatar_url: null, role: 'organization_administrator', status: 'active' }),
  );

  const employees: Row[] = personaList
    .filter((p) => p.employeeId)
    .map((p) =>
      ts({
        id: p.employeeId,
        tenant_id: T,
        profile_id: p.profileId,
        employee_number: p.employeeNumber,
        first_name: p.firstName,
        last_name: p.lastName,
        email: p.email,
        phone: null,
        department_id: p.departmentId,
        position_id: p.positionId,
        supervisor_id: p.role === 'employee' || p.role === 'employee_two' ? PERSONAS.supervisor.employeeId : null,
        region_id: ID.regionGauteng,
        home_site_id: p.role === 'employee' || p.role === 'employee_two' || p.role === 'supervisor' || p.role === 'site_manager' ? ID.siteTowerA : null,
        employment_type: 'full_time',
        employment_status: 'active',
        employment_start_date: '2025-03-03',
        employment_end_date: null,
      }),
    );
  employees.push(
    ts({ id: ID.rivalEmployee, tenant_id: ID.rivalOrg, profile_id: ID.rivalProfile, employee_number: 'RV-0001', first_name: 'Rhea', last_name: 'Rival', email: 'rhea.rival@rivalservices.example', phone: null, department_id: null, position_id: null, supervisor_id: null, region_id: null, home_site_id: null, employment_type: 'full_time', employment_status: 'active', employment_start_date: '2024-01-01', employment_end_date: null }),
  );

  const thabo = PERSONAS.employee;
  const lerato = PERSONAS.employee_two;
  const sarah = PERSONAS.supervisor;
  const shiftStart = '2026-09-21T04:00:00.000Z';
  const shiftEnd = '2026-09-21T12:00:00.000Z';

  return {
    organizations: [
      ts({ id: T, name: 'Brightway Facilities (Demo)', registration_number: '2020/000001/07', industry: 'Commercial cleaning', email: 'ops@brightway.example', phone: null, website: null, logo_url: null, address: '1 Demo Road, Johannesburg', timezone: 'Africa/Johannesburg', currency: 'ZAR', language: 'en', status: 'active' }),
      ts({ id: ID.rivalOrg, name: 'Rival Services (Demo)', registration_number: null, industry: 'Commercial cleaning', email: null, phone: null, website: null, logo_url: null, address: null, timezone: 'Africa/Johannesburg', currency: 'ZAR', language: 'en', status: 'active' }),
    ],
    profiles,
    employees,
    regions: [
      ts({ id: ID.regionGauteng, tenant_id: T, name: 'Gauteng', code: 'GP', status: 'active' }),
      ts({ id: ID.regionWesternCape, tenant_id: T, name: 'Western Cape', code: 'WC', status: 'active' }),
    ],
    clients: [
      ts({ id: ID.clientHarbour, tenant_id: T, region_id: ID.regionGauteng, name: 'Harbour Point Offices', industry: 'Commercial property', primary_contact_name: 'Chris Client', primary_contact_email: 'chris.client@harbourpoint.example', primary_contact_phone: null, status: 'active' }),
      ts({ id: ID.clientNorthgate, tenant_id: T, region_id: ID.regionGauteng, name: 'Northgate Mall', industry: 'Retail', primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active' }),
      ts({ id: ID.rivalClient, tenant_id: ID.rivalOrg, region_id: null, name: 'Rival Client Ltd', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active' }),
    ],
    client_contacts: [
      ts({ id: uuid(23, 1), tenant_id: T, client_id: ID.clientHarbour, name: 'Chris Client', role_title: 'Facilities Manager', email: 'chris.client@harbourpoint.example', phone: null, is_primary: true, notes: null }),
    ],
    contracts: [
      ts({ id: ID.contractHarbour, tenant_id: T, client_id: ID.clientHarbour, contract_number: 'HP-2026-001', start_date: '2026-01-01', end_date: '2026-12-31', status: 'active', responsible_manager_id: PERSONAS.operations_manager.profileId, sla_notes: 'Daily office and washroom cleaning, 06:00–14:00.' }),
      ts({ id: ID.contractNorthgate, tenant_id: T, client_id: ID.clientNorthgate, contract_number: 'NG-2026-002', start_date: '2026-03-01', end_date: dateOffset(30), status: 'active', responsible_manager_id: null, sla_notes: null }),
    ],
    sites: [
      ts({ id: ID.siteTowerA, tenant_id: T, client_id: ID.clientHarbour, region_id: ID.regionGauteng, name: 'Harbour Point – Tower A', address: '10 Harbour Street, Sandton', site_type: 'office', status: 'active' }),
      ts({ id: ID.siteAtrium, tenant_id: T, client_id: ID.clientNorthgate, region_id: ID.regionGauteng, name: 'Northgate Mall – Main Atrium', address: '2 Northgate Drive, Randburg', site_type: 'retail', status: 'active' }),
      ts({ id: ID.siteFoodCourt, tenant_id: T, client_id: ID.clientNorthgate, region_id: ID.regionGauteng, name: 'Northgate Mall – Food Court', address: '2 Northgate Drive, Randburg', site_type: 'retail', status: 'active' }),
      ts({ id: ID.rivalSite, tenant_id: ID.rivalOrg, client_id: ID.rivalClient, region_id: null, name: 'Rival Site', address: null, site_type: null, status: 'active' }),
    ],
    contract_sites: [
      { contract_id: ID.contractHarbour, site_id: ID.siteTowerA, tenant_id: T, created_at: created },
      { contract_id: ID.contractNorthgate, site_id: ID.siteAtrium, tenant_id: T, created_at: created },
      { contract_id: ID.contractNorthgate, site_id: ID.siteFoodCourt, tenant_id: T, created_at: created },
    ],
    departments: [
      ts({ id: ID.deptCleaning, tenant_id: T, name: 'Cleaning Operations' }),
      ts({ id: ID.deptHr, tenant_id: T, name: 'Human Resources' }),
    ],
    positions: [
      ts({ id: ID.posCleaner, tenant_id: T, department_id: ID.deptCleaning, title: 'Cleaner', status: 'active' }),
      ts({ id: ID.posSupervisor, tenant_id: T, department_id: ID.deptCleaning, title: 'Site Supervisor', status: 'active' }),
    ],
    teams: [ts({ id: ID.teamTowerADay, tenant_id: T, site_id: ID.siteTowerA, name: 'Tower A Day Team', lead_employee_id: sarah.employeeId, status: 'active' })],
    team_members: [
      { team_id: ID.teamTowerADay, employee_id: thabo.employeeId, tenant_id: T, joined_at: created },
      { team_id: ID.teamTowerADay, employee_id: lerato.employeeId, tenant_id: T, joined_at: created },
    ],
    site_assignments: [
      ts({ id: uuid(24, 1), tenant_id: T, site_id: ID.siteTowerA, employee_id: thabo.employeeId, role_on_site: 'Cleaner', start_date: '2025-03-03', end_date: null }),
      ts({ id: uuid(24, 2), tenant_id: T, site_id: ID.siteTowerA, employee_id: lerato.employeeId, role_on_site: 'Cleaner', start_date: '2025-03-03', end_date: null }),
      ts({ id: uuid(24, 3), tenant_id: T, site_id: ID.siteTowerA, employee_id: sarah.employeeId, role_on_site: 'Supervisor', start_date: '2025-03-03', end_date: null }),
    ],
    site_staffing_requirements: [ts({ id: uuid(25, 1), tenant_id: T, site_id: ID.siteTowerA, label: 'Day cleaners', required_count: 3 })],
    shift_definitions: [
      ts({ id: ID.shiftDefDay, tenant_id: T, name: 'Day 06:00–14:00', start_time: '06:00:00', end_time: '14:00:00', is_overnight: false, break_minutes: 30, status: 'active' }),
      ts({ id: ID.shiftDefNight, tenant_id: T, name: 'Night 22:00–06:00', start_time: '22:00:00', end_time: '06:00:00', is_overnight: true, break_minutes: 30, status: 'active' }),
    ],
    shifts: [
      ts({ id: uuid(26, 1), tenant_id: T, site_id: ID.siteTowerA, employee_id: thabo.employeeId, supervisor_id: sarah.employeeId, shift_definition_id: ID.shiftDefDay, starts_at: shiftStart, ends_at: shiftEnd, status: 'scheduled', notes: null }),
      ts({ id: uuid(26, 2), tenant_id: T, site_id: ID.siteTowerA, employee_id: lerato.employeeId, supervisor_id: sarah.employeeId, shift_definition_id: ID.shiftDefDay, starts_at: shiftStart, ends_at: shiftEnd, status: 'scheduled', notes: null }),
    ],
    attendance_policies: [ts({ id: uuid(27, 1), tenant_id: T, grace_period_minutes: 5, early_departure_threshold_minutes: 5, overtime_threshold_minutes: 15 })],
    attendance_records: [
      ts({ id: uuid(28, 1), tenant_id: T, shift_id: uuid(26, 1), site_id: ID.siteTowerA, employee_id: thabo.employeeId, status: 'unconfirmed', clock_in_at: null, clock_out_at: null, recorded_by: null, notes: null, late_minutes: null, early_departure_minutes: null, worked_minutes: null, overtime_minutes: null }),
    ],
    leave_types: [
      ts({ id: ID.leaveAnnual, tenant_id: T, name: 'Annual', is_paid: true, requires_documentation: false, default_annual_days: 15, status: 'active' }),
      ts({ id: ID.leaveSick, tenant_id: T, name: 'Sick', is_paid: true, requires_documentation: true, default_annual_days: 30, status: 'active' }),
      ts({ id: ID.leaveFamily, tenant_id: T, name: 'Family Responsibility', is_paid: true, requires_documentation: false, default_annual_days: 3, status: 'active' }),
    ],
    leave_policies: [
      ts({ id: uuid(29, 1), tenant_id: T, leave_type_id: ID.leaveAnnual, default_annual_days: 15, max_carry_over_days: 5, min_notice_days: 0, requires_documentation: false, max_consecutive_days: null }),
    ],
    leave_balances: [
      ts({ id: uuid(30, 1), tenant_id: T, employee_id: thabo.employeeId, leave_type_id: ID.leaveAnnual, period_year: 2026, opening_balance: 15, accrued: 0, used: 2, pending: 0, adjustment: 0, carried_over: 0, remaining: 13 }),
      ts({ id: uuid(30, 2), tenant_id: T, employee_id: lerato.employeeId, leave_type_id: ID.leaveAnnual, period_year: 2026, opening_balance: 15, accrued: 0, used: 0, pending: 3, adjustment: 0, carried_over: 0, remaining: 12 }),
    ],
    leave_requests: [
      ts({ id: uuid(31, 1), tenant_id: T, employee_id: lerato.employeeId, leave_type_id: ID.leaveAnnual, start_date: dateOffset(14), end_date: dateOffset(16), is_half_day: false, half_day_period: null, reason: 'Family visit', status: 'pending', decided_by: null, decided_at: null, decision_notes: null, supporting_document_ref: null, cancelled_at: null, cancelled_by: null }),
    ],
    tasks: [
      ts({ id: ID.taskWashrooms, tenant_id: T, site_id: ID.siteTowerA, assignee_id: thabo.employeeId, team_id: null, supervisor_id: sarah.employeeId, title: 'Clean ground-floor washrooms', description: 'Clean, disinfect and restock all ground-floor washrooms.', priority: 'normal', status: 'open', due_at: '2026-09-21T09:00:00.000Z', completed_at: null, completed_by: null, requires_evidence: false, created_by: sarah.profileId }),
      ts({ id: ID.taskReception, tenant_id: T, site_id: ID.siteTowerA, assignee_id: lerato.employeeId, team_id: null, supervisor_id: sarah.employeeId, title: 'Polish reception floor', description: null, priority: 'high', status: 'completed', due_at: '2026-09-20T09:00:00.000Z', completed_at: '2026-09-20T08:30:00.000Z', completed_by: lerato.profileId, requires_evidence: true, created_by: sarah.profileId }),
      ts({ id: ID.taskKitchen, tenant_id: T, site_id: ID.siteTowerA, assignee_id: thabo.employeeId, team_id: null, supervisor_id: sarah.employeeId, title: 'Deep clean staff kitchen', description: null, priority: 'low', status: 'open', due_at: '2026-09-18T09:00:00.000Z', completed_at: null, completed_by: null, requires_evidence: false, created_by: sarah.profileId }),
    ],
    task_checklist_items: [
      ts({ id: uuid(32, 1), tenant_id: T, task_id: ID.taskWashrooms, label: 'Disinfect fixtures', sort_order: 1, is_completed: false, completed_by: null, completed_at: null, notes: null }),
      ts({ id: uuid(32, 2), tenant_id: T, task_id: ID.taskWashrooms, label: 'Restock consumables', sort_order: 2, is_completed: false, completed_by: null, completed_at: null, notes: null }),
      ts({ id: uuid(32, 3), tenant_id: T, task_id: ID.taskWashrooms, label: 'Mop floors', sort_order: 3, is_completed: false, completed_by: null, completed_at: null, notes: null }),
    ],
    task_evidence: [
      ts({ id: uuid(33, 1), tenant_id: T, task_id: ID.taskReception, kind: 'note', note: 'Floor polished, signed off by client reception.', submitted_by: lerato.profileId }),
    ],
    incidents: [
      ts({ id: ID.incidentSlip, tenant_id: T, reference_number: 'INC-2026-000001', site_id: ID.siteTowerA, contract_id: ID.contractHarbour, category: 'workplace_safety', severity: 'medium', status: 'investigating', occurred_at: '2026-09-19T07:30:00.000Z', reported_by: thabo.profileId, description: 'Slip near the lobby entrance after mopping.', investigation_notes: null, corrective_action_summary: null, closed_by: null, closed_at: null }),
    ],
    incident_actions: [
      ts({ id: ID.actionSignage, tenant_id: T, incident_id: ID.incidentSlip, description: 'Place wet-floor signage at lobby entrance', owner_profile_id: sarah.profileId, due_date: dateOffset(2), status: 'open', completed_at: null, verified_by: null, verified_at: null }),
    ],
    compliance_requirements: [
      ts({ id: ID.reqCoida, tenant_id: T, name: 'COIDA letter of good standing', category: 'legal', description: null, applies_to_scope: 'site', recurrence_interval_days: 365, is_active: true, created_by: PERSONAS.organization_administrator.profileId }),
    ],
    compliance_records: [
      ts({ id: ID.recordCoida, tenant_id: T, requirement_id: ID.reqCoida, site_id: ID.siteTowerA, client_id: null, contract_id: null, responsible_profile_id: sarah.profileId, status: 'pending', due_date: dateOffset(10), completed_date: null, expiry_date: null, evidence_storage_path: null, verified_by: null, verified_at: null, notes: null }),
    ],
    employee_documents: [
      ts({ id: ID.docChemical, tenant_id: T, employee_id: thabo.employeeId, document_type: 'certificate', file_name: 'chemical-handling.pdf', mime_type: 'application/pdf', file_size_bytes: 120000, storage_path: `${T}/${thabo.employeeId}/${ID.docChemical}-chemical-handling.pdf`, version: 1, supersedes_document_id: null, status: 'verified', expiry_date: '2027-06-30', uploaded_by: thabo.profileId, verified_by: PERSONAS.hr_user.profileId, verified_at: created, review_notes: null }),
      ts({ id: ID.docFirstAid, tenant_id: T, employee_id: thabo.employeeId, document_type: 'certificate', file_name: 'first-aid.pdf', mime_type: 'application/pdf', file_size_bytes: 98000, storage_path: `${T}/${thabo.employeeId}/${ID.docFirstAid}-first-aid.pdf`, version: 1, supersedes_document_id: null, status: 'pending_review', expiry_date: dateOffset(20), uploaded_by: thabo.profileId, verified_by: null, verified_at: null, review_notes: null }),
    ],
    assets: [
      ts({ id: ID.assetScrubber, tenant_id: T, asset_number: 'FS-01', name: 'Floor scrubber', category: 'equipment', serial_number: 'SN-FS-0001', site_id: ID.siteTowerA, custodian_employee_id: null, status: 'available', condition: 'good', acquisition_date: '2025-05-01', acquisition_cost: 38000, notes: null }),
      ts({ id: ID.assetVacuum, tenant_id: T, asset_number: 'VC-07', name: 'Industrial vacuum', category: 'equipment', serial_number: null, site_id: ID.siteTowerA, custodian_employee_id: thabo.employeeId, status: 'assigned', condition: 'fair', acquisition_date: '2024-11-12', acquisition_cost: 6500, notes: null }),
    ],
    inventory_items: [
      ts({ id: ID.itemCleaner, tenant_id: T, sku: 'CHEM-001', name: 'Multi-surface cleaner 5L', category: 'consumables', unit: 'each', reorder_threshold: 10, is_active: true }),
      ts({ id: ID.itemMopHeads, tenant_id: T, sku: 'EQP-014', name: 'Mop heads', category: 'consumables', unit: 'each', reorder_threshold: 20, is_active: true }),
    ],
    inventory_movements: [
      { id: uuid(34, 1), tenant_id: T, item_id: ID.itemCleaner, site_id: ID.siteTowerA, movement_type: 'receipt', quantity: 24, reference: 'GRN-0001', performed_by: PERSONAS.operations_manager.profileId, created_at: created },
      { id: uuid(34, 2), tenant_id: T, item_id: ID.itemMopHeads, site_id: ID.siteTowerA, movement_type: 'receipt', quantity: 8, reference: 'GRN-0002', performed_by: PERSONAS.operations_manager.profileId, created_at: created },
    ],
    procurement_requests: [
      ts({ id: ID.procMops, tenant_id: T, requested_by: sarah.profileId, site_id: ID.siteTowerA, item_description: 'Mop heads x20', quantity: 20, estimated_cost: 600, status: 'submitted', approved_by: null, approved_at: null, rejected_reason: null }),
    ],
    skills: [
      ts({ id: ID.skillChemical, tenant_id: T, name: 'Chemical handling', category: 'safety' }),
      ts({ id: ID.skillFirstAid, tenant_id: T, name: 'First aid', category: 'safety' }),
    ],
    employee_skills: [
      ts({ id: uuid(35, 1), tenant_id: T, employee_id: thabo.employeeId, skill_id: ID.skillChemical, proficiency_level: 'intermediate', evidence_document_id: ID.docChemical, verified_by: null, verified_at: null }),
    ],
    training_programs: [ts({ id: ID.programManualHandling, tenant_id: T, name: 'Manual handling', description: null, category: 'safety', is_active: true })],
    training_enrollments: [
      ts({ id: uuid(36, 1), tenant_id: T, training_program_id: ID.programManualHandling, employee_id: thabo.employeeId, status: 'scheduled', enrolled_at: created, completed_at: null, result: null, resulting_qualification_id: null }),
    ],
    performance_reviews: [
      ts({ id: ID.reviewThabo, tenant_id: T, employee_id: thabo.employeeId, reviewer_profile_id: sarah.profileId, review_period_start: '2026-01-01', review_period_end: '2026-06-30', status: 'acknowledgement', overall_rating: 4, manager_comments: 'Reliable and thorough.', employee_comments: null, finalized_at: null }),
    ],
    sla_definitions: [
      ts({ id: uuid(37, 1), tenant_id: T, contract_id: ID.contractHarbour, site_id: ID.siteTowerA, name: 'Daily task completion ≥ 95%', metric_type: 'task_completion_rate', target_value: 95, threshold_operator: 'gte', measurement_period: 'monthly', is_active: true }),
    ],
    notifications: personaList
      .filter((p) => p.role !== 'platform_administrator')
      .map((p, i) => ({
        id: uuid(38, i + 1),
        tenant_id: T,
        recipient_profile_id: p.profileId,
        type: 'task_assigned',
        title: 'Welcome to Sebetsa',
        body: 'Your workspace is ready.',
        related_entity_table: null,
        related_entity_id: null,
        link_path: '/dashboard',
        email_status: 'not_sent',
        read_at: null,
        created_at: created,
      })),
  };
}
