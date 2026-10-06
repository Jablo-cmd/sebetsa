import type { Row, RpcContext, RpcHandler } from './fakeBackend';

/**
 * Behavioural stand-ins for Sebetsa's SECURITY DEFINER RPCs. They mirror the
 * database's rules (permission tiers, state machines, balances, separation of
 * duties, error messages) so UI tests exercise realistic outcomes — including
 * failures. The database remains the source of truth: supabase/rls-tests/
 * proves the real functions; `fakeBackend.unit.ts` proves every function
 * named here exists in the migrations.
 */

const MANAGE_OPS = ['organization_administrator', 'operations_manager', 'regional_manager', 'site_manager', 'supervisor'];
const MANAGE_EMP = ['organization_administrator', 'operations_manager', 'hr_user'];
const APPROVE_LEAVE = ['organization_administrator', 'operations_manager', 'regional_manager', 'hr_user'];
const ORG_STRUCT = ['organization_administrator', 'operations_manager'];

type Ctx = RpcContext;

function can(ctx: Ctx, roles: string[]): boolean {
  return ctx.session.role === 'platform_administrator' || roles.includes(ctx.session.role);
}

function require_(ctx: Ctx, roles: string[], message: string): void {
  if (!can(ctx, roles)) ctx.fail(`insufficient_privilege: ${message}`, '42501', 403);
}

function row(ctx: Ctx, table: string, id: unknown, label: string): Row {
  const found = ctx.backend.visible(table).find((r) => r.id === id);
  if (!found) ctx.fail(`not_found: no ${label} ${String(id)}`);
  return found;
}

function employeeProfile(ctx: Ctx, employeeId: unknown): string | null {
  const emp = ctx.backend.table('employees').find((e) => e.id === employeeId);
  return (emp?.profile_id as string | null | undefined) ?? null;
}

function isOwnEmployee(ctx: Ctx, employeeId: unknown): boolean {
  return employeeProfile(ctx, employeeId) === ctx.session.userId;
}

/** Mirrors public.assert_separation_of_duties(). */
function sod(ctx: Ctx, rule: string, subjects: (string | null | undefined)[]): void {
  if (subjects.some((s) => s && s === ctx.session.userId)) {
    ctx.fail(`separation_of_duties: ${rule} — you cannot act on a record you raised or that concerns you`, '42501', 403);
  }
}

function audit(ctx: Ctx, tenantId: unknown, action: string, table: string, entityId: unknown, after?: unknown): void {
  ctx.backend.table('audit_log').push({
    id: ctx.backend.newId(),
    tenant_id: tenantId,
    actor_profile_id: ctx.session.userId,
    action,
    entity_table: table,
    entity_id: entityId,
    before: null,
    after: after ?? null,
    category: 'business',
    outcome: 'success',
    created_at: ctx.now,
  });
}

function insert(ctx: Ctx, table: string, data: Row): Row {
  const created: Row = { id: ctx.backend.newId(), created_at: ctx.now, updated_at: ctx.now, ...data };
  ctx.backend.table(table).push(created);
  return created;
}

function touch(ctx: Ctx, target: Row, patch: Row): Row {
  Object.assign(target, patch, 'updated_at' in target ? { updated_at: ctx.now } : {});
  return target;
}

function tenant(ctx: Ctx): string {
  return ctx.session.tenantId ?? '';
}

// ------------------------------------------------------------------- leave

function leaveDays(r: Row): number {
  if (r.is_half_day) return 0.5;
  const start = Date.parse(`${r.start_date}T00:00:00Z`);
  const end = Date.parse(`${r.end_date}T00:00:00Z`);
  return Math.round((end - start) / 86_400_000) + 1;
}

function balanceFor(ctx: Ctx, r: Row): Row {
  const year = Number(String(r.start_date).slice(0, 4));
  let balance = ctx.backend.table('leave_balances').find((b) => b.employee_id === r.employee_id && b.leave_type_id === r.leave_type_id && b.period_year === year);
  if (!balance) {
    balance = insert(ctx, 'leave_balances', {
      tenant_id: r.tenant_id, employee_id: r.employee_id, leave_type_id: r.leave_type_id, period_year: year,
      opening_balance: 0, accrued: 0, used: 0, pending: 0, adjustment: 0, carried_over: 0, remaining: 0,
    });
  }
  return balance;
}

function recalc(ctx: Ctx, b: Row): void {
  const remaining = Number(b.opening_balance) + Number(b.accrued) + Number(b.adjustment) + Number(b.carried_over) - Number(b.used) - Number(b.pending);
  touch(ctx, b, { remaining });
}

const leave: Record<string, RpcHandler> = {
  submit_leave_request: (a, ctx) => {
    const emp = row(ctx, 'employees', a.p_employee_id, 'employee');
    if (!(isOwnEmployee(ctx, emp.id) || can(ctx, MANAGE_EMP))) ctx.fail('insufficient_privilege: cannot submit leave for this employee', '42501', 403);
    if (String(a.p_end_date) < String(a.p_start_date)) ctx.fail('invalid_date_range: end date is before start date');
    const type = row(ctx, 'leave_types', a.p_leave_type_id, 'leave type');
    if (type.requires_documentation && !a.p_supporting_document_ref) ctx.fail('documentation_required: this leave type requires supporting documentation');
    const created = insert(ctx, 'leave_requests', {
      tenant_id: emp.tenant_id, employee_id: emp.id, leave_type_id: type.id, start_date: a.p_start_date, end_date: a.p_end_date,
      is_half_day: Boolean(a.p_is_half_day), half_day_period: a.p_half_day_period ?? null, reason: a.p_reason ?? null,
      status: 'pending', decided_by: null, decided_at: null, decision_notes: null, supporting_document_ref: a.p_supporting_document_ref ?? null,
      cancelled_at: null, cancelled_by: null,
    });
    const b = balanceFor(ctx, created);
    touch(ctx, b, { pending: Number(b.pending) + leaveDays(created) });
    recalc(ctx, b);
    audit(ctx, emp.tenant_id, 'leave_requested', 'leave_requests', created.id);
    return created;
  },
  cancel_leave_request: (a, ctx) => {
    const r = row(ctx, 'leave_requests', a.p_leave_request_id, 'leave request');
    if (!(isOwnEmployee(ctx, r.employee_id) || can(ctx, APPROVE_LEAVE))) ctx.fail('insufficient_privilege: cannot cancel this leave request', '42501', 403);
    if (r.status !== 'pending') ctx.fail(`invalid_leave_status_transition: cannot cancel a ${r.status} request`);
    const b = balanceFor(ctx, r);
    touch(ctx, b, { pending: Number(b.pending) - leaveDays(r) });
    recalc(ctx, b);
    return touch(ctx, r, { status: 'cancelled', cancelled_at: ctx.now, cancelled_by: ctx.session.userId });
  },
  approve_leave_request: (a, ctx) => {
    const r = row(ctx, 'leave_requests', a.p_leave_request_id, 'leave request');
    require_(ctx, APPROVE_LEAVE, 'cannot approve leave for this tenant');
    sod(ctx, 'leave.decide', [employeeProfile(ctx, r.employee_id)]);
    if (r.status !== 'pending') ctx.fail(`invalid_leave_status_transition: cannot approve a ${r.status} request`);
    const b = balanceFor(ctx, r);
    touch(ctx, b, { pending: Number(b.pending) - leaveDays(r), used: Number(b.used) + leaveDays(r) });
    recalc(ctx, b);
    audit(ctx, r.tenant_id, 'leave_approved', 'leave_requests', r.id);
    return touch(ctx, r, { status: 'approved', decided_by: ctx.session.userId, decided_at: ctx.now, decision_notes: a.p_decision_notes ?? null });
  },
  reject_leave_request: (a, ctx) => {
    const r = row(ctx, 'leave_requests', a.p_leave_request_id, 'leave request');
    require_(ctx, APPROVE_LEAVE, 'cannot reject leave for this tenant');
    sod(ctx, 'leave.decide', [employeeProfile(ctx, r.employee_id)]);
    if (r.status !== 'pending') ctx.fail(`invalid_leave_status_transition: cannot reject a ${r.status} request`);
    const b = balanceFor(ctx, r);
    touch(ctx, b, { pending: Number(b.pending) - leaveDays(r) });
    recalc(ctx, b);
    return touch(ctx, r, { status: 'rejected', decided_by: ctx.session.userId, decided_at: ctx.now, decision_notes: a.p_decision_notes ?? null });
  },
  revoke_leave_request: (a, ctx) => {
    const r = row(ctx, 'leave_requests', a.p_leave_request_id, 'leave request');
    require_(ctx, APPROVE_LEAVE, 'cannot revoke leave for this tenant');
    sod(ctx, 'leave.decide', [employeeProfile(ctx, r.employee_id)]);
    if (r.status !== 'approved') ctx.fail(`invalid_leave_status_transition: cannot revoke a ${r.status} request`);
    const b = balanceFor(ctx, r);
    touch(ctx, b, { used: Number(b.used) - leaveDays(r) });
    recalc(ctx, b);
    return touch(ctx, r, { status: 'revoked', decided_by: ctx.session.userId, decided_at: ctx.now, decision_notes: a.p_decision_notes ?? null });
  },
  adjust_leave_balance: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot adjust leave balances for this tenant');
    const emp = row(ctx, 'employees', a.p_employee_id, 'employee');
    const probe = { tenant_id: emp.tenant_id, employee_id: emp.id, leave_type_id: a.p_leave_type_id, start_date: `${a.p_period_year}-01-01` };
    const b = balanceFor(ctx, probe);
    touch(ctx, b, { adjustment: Number(b.adjustment) + Number(a.p_amount) });
    recalc(ctx, b);
    audit(ctx, emp.tenant_id, 'leave_balance_adjusted', 'leave_balances', b.id);
    return b;
  },
  get_leave_affected_shifts: (a, ctx) => {
    const r = row(ctx, 'leave_requests', a.p_leave_request_id, 'leave request');
    const from = Date.parse(`${r.start_date}T00:00:00Z`);
    const to = Date.parse(`${r.end_date}T00:00:00Z`) + 86_400_000;
    return ctx.backend.visible('shifts').filter((s) => s.employee_id === r.employee_id && s.status !== 'cancelled' && Date.parse(String(s.starts_at)) < to && Date.parse(String(s.ends_at)) > from);
  },
};

// -------------------------------------------------------------- attendance

function minutes(from: string, to: string): number {
  return Math.floor((Date.parse(to) - Date.parse(from)) / 60_000);
}

const attendance: Record<string, RpcHandler> = {
  clock_in: (a, ctx) => {
    const emp = row(ctx, 'employees', a.p_employee_id, 'employee');
    if (!(isOwnEmployee(ctx, emp.id) || can(ctx, MANAGE_OPS))) ctx.fail('insufficient_privilege: cannot clock in this employee', '42501', 403);
    const open = ctx.backend.table('attendance_records').find((r) => r.employee_id === emp.id && r.clock_in_at && !r.clock_out_at);
    if (open) ctx.fail('already_clocked_in: employee already has an open attendance record');
    const shift = a.p_shift_id ? ctx.backend.table('shifts').find((s) => s.id === a.p_shift_id) : undefined;
    const grace = Number(ctx.backend.table('attendance_policies')[0]?.grace_period_minutes ?? 5);
    const late = shift ? Math.max(0, minutes(String(shift.starts_at), ctx.now) - grace) : 0;
    let rec = ctx.backend.table('attendance_records').find((r) => r.shift_id === (a.p_shift_id ?? null) && r.employee_id === emp.id && !r.clock_in_at);
    const patch = { clock_in_at: ctx.now, status: late > 0 ? 'late' : 'present', late_minutes: late > 0 ? late : null, recorded_by: ctx.session.userId };
    rec = rec
      ? touch(ctx, rec, patch)
      : insert(ctx, 'attendance_records', { tenant_id: emp.tenant_id, shift_id: a.p_shift_id ?? null, site_id: a.p_site_id, employee_id: emp.id, clock_out_at: null, notes: null, early_departure_minutes: null, worked_minutes: null, overtime_minutes: null, ...patch });
    audit(ctx, emp.tenant_id, 'attendance_clock_in', 'attendance_records', rec.id);
    return rec;
  },
  clock_out: (a, ctx) => {
    const rec = row(ctx, 'attendance_records', a.p_attendance_record_id, 'attendance record');
    if (!(isOwnEmployee(ctx, rec.employee_id) || can(ctx, MANAGE_OPS))) ctx.fail('insufficient_privilege: cannot clock out this employee', '42501', 403);
    if (!rec.clock_in_at || rec.clock_out_at) ctx.fail('invalid_sequence: record is not clocked in');
    const breaks = ctx.backend.table('attendance_breaks').filter((b) => b.attendance_record_id === rec.id && b.break_end);
    const breakMinutes = breaks.reduce((sum, b) => sum + minutes(String(b.break_start), String(b.break_end)), 0);
    const worked = Math.max(0, minutes(String(rec.clock_in_at), ctx.now) - breakMinutes);
    audit(ctx, rec.tenant_id, 'attendance_clock_out', 'attendance_records', rec.id);
    return touch(ctx, rec, { clock_out_at: ctx.now, worked_minutes: worked });
  },
  start_break: (a, ctx) => {
    const rec = row(ctx, 'attendance_records', a.p_attendance_record_id, 'attendance record');
    if (!rec.clock_in_at || rec.clock_out_at) ctx.fail('invalid_sequence: record is not clocked in');
    if (ctx.backend.table('attendance_breaks').some((b) => b.attendance_record_id === rec.id && !b.break_end)) ctx.fail('invalid_sequence: a break is already in progress');
    return insert(ctx, 'attendance_breaks', { tenant_id: rec.tenant_id, attendance_record_id: rec.id, break_start: ctx.now, break_end: null });
  },
  end_break: (a, ctx) => {
    const open = ctx.backend.table('attendance_breaks').find((b) => b.attendance_record_id === a.p_attendance_record_id && !b.break_end);
    return touch(ctx, open ?? ctx.fail('invalid_sequence: no break in progress'), { break_end: ctx.now });
  },
  request_attendance_correction: (a, ctx) => {
    const rec = row(ctx, 'attendance_records', a.p_attendance_record_id, 'attendance record');
    if (!(isOwnEmployee(ctx, rec.employee_id) || can(ctx, MANAGE_OPS))) ctx.fail('insufficient_privilege: cannot request a correction for this record', '42501', 403);
    const created = insert(ctx, 'attendance_corrections', {
      tenant_id: rec.tenant_id, attendance_record_id: rec.id, field: a.p_field, previous_value: rec[String(a.p_field)] ?? null, new_value: a.p_new_value,
      reason: a.p_reason, status: 'pending', requested_by: ctx.session.userId, reviewed_by: null, reviewed_at: null, review_notes: null,
    });
    audit(ctx, rec.tenant_id, 'attendance_correction_requested', 'attendance_corrections', created.id);
    return created;
  },
  decide_attendance_correction: (a, ctx) => {
    const c = row(ctx, 'attendance_corrections', a.p_correction_id, 'correction');
    require_(ctx, MANAGE_OPS, 'cannot decide attendance corrections');
    const rec = row(ctx, 'attendance_records', c.attendance_record_id, 'attendance record');
    sod(ctx, 'attendance_correction.decide', [c.requested_by as string, employeeProfile(ctx, rec.employee_id)]);
    if (c.status !== 'pending') ctx.fail(`invalid_transition: correction is already ${c.status}`);
    if (a.p_approve) touch(ctx, rec, { [String(c.field)]: c.new_value });
    return touch(ctx, c, { status: a.p_approve ? 'approved' : 'rejected', reviewed_by: ctx.session.userId, reviewed_at: ctx.now, review_notes: a.p_review_notes ?? null });
  },
};

// ------------------------------------------------------------------- tasks

const tasks: Record<string, RpcHandler> = {
  complete_task: (a, ctx) => {
    const t = row(ctx, 'tasks', a.p_task_id, 'task');
    if (!(isOwnEmployee(ctx, t.assignee_id) || can(ctx, MANAGE_OPS))) ctx.fail('insufficient_privilege: cannot complete this task', '42501', 403);
    if (!['open', 'in_progress', 'escalated'].includes(String(t.status))) ctx.fail(`invalid_task_status_transition: only an open/in_progress/escalated task can be completed (current status: ${t.status})`);
    const incomplete = ctx.backend.table('task_checklist_items').filter((c) => c.task_id === t.id && !c.is_completed).length;
    if (incomplete > 0) ctx.fail(`checklist_incomplete: ${incomplete} checklist item(s) still incomplete`);
    if (t.requires_evidence && ctx.backend.table('task_evidence').filter((e) => e.task_id === t.id).length === 0) ctx.fail('evidence_required: this task requires at least one evidence entry before it can be completed');
    audit(ctx, t.tenant_id, 'task_completed', 'tasks', t.id);
    return touch(ctx, t, { status: 'completed', completed_at: ctx.now, completed_by: ctx.session.userId });
  },
  verify_task: (a, ctx) => {
    const t = row(ctx, 'tasks', a.p_task_id, 'task');
    require_(ctx, MANAGE_OPS, 'cannot verify tasks for this tenant');
    sod(ctx, 'task.verify', [t.completed_by as string, employeeProfile(ctx, t.assignee_id)]);
    if (t.status !== 'completed') ctx.fail(`invalid_task_status_transition: only a completed task can be verified (current status: ${t.status})`);
    audit(ctx, t.tenant_id, 'task_verified', 'tasks', t.id);
    return touch(ctx, t, { status: 'verified' });
  },
  escalate_overdue_tasks: (_a, ctx) => {
    require_(ctx, MANAGE_OPS, 'cannot escalate tasks for this tenant');
    const overdue = ctx.backend.visible('tasks').filter((t) => ['open', 'in_progress'].includes(String(t.status)) && t.due_at && String(t.due_at) < ctx.now);
    for (const t of overdue) {
      touch(ctx, t, { status: 'escalated' });
      const supervisor = employeeProfile(ctx, t.supervisor_id);
      if (supervisor) {
        insert(ctx, 'notifications', { tenant_id: t.tenant_id, recipient_profile_id: supervisor, type: 'task_escalated', title: `Task overdue: ${t.title}`, body: 'A task assigned to your team is now overdue and has been escalated.', related_entity_table: 'tasks', related_entity_id: t.id, link_path: null, email_status: 'not_sent', read_at: null });
      }
      audit(ctx, t.tenant_id, 'task_escalated', 'tasks', t.id);
    }
    return overdue;
  },
  generate_recurring_tasks: (_a, ctx) => {
    require_(ctx, MANAGE_OPS, 'cannot generate tasks for this tenant');
    const today = ctx.now.slice(0, 10);
    const created: Row[] = [];
    for (const tpl of ctx.backend.visible('task_templates').filter((x) => x.status === 'active' && x.recurrence_frequency)) {
      const start = tpl.recurrence_frequency === 'daily' ? today : tpl.recurrence_frequency === 'monthly' ? `${today.slice(0, 7)}-01` : today;
      if (tpl.last_generated_on && String(tpl.last_generated_on) >= start) continue;
      const task = insert(ctx, 'tasks', { tenant_id: tpl.tenant_id, site_id: tpl.site_id, assignee_id: tpl.default_assignee_id, team_id: tpl.default_team_id, supervisor_id: null, title: tpl.title, description: tpl.description, priority: tpl.priority ?? 'normal', status: 'open', due_at: null, completed_at: null, completed_by: null, requires_evidence: Boolean(tpl.requires_evidence), created_by: ctx.session.userId });
      touch(ctx, tpl, { last_generated_on: start });
      audit(ctx, tpl.tenant_id, 'task_generated_from_template', 'tasks', task.id);
      created.push(task);
    }
    return created;
  },
  reassign_task: (a, ctx) => {
    const t = row(ctx, 'tasks', a.p_task_id, 'task');
    require_(ctx, MANAGE_OPS, 'cannot reassign tasks for this tenant');
    row(ctx, 'employees', a.p_new_assignee_id, 'employee');
    return touch(ctx, t, { assignee_id: a.p_new_assignee_id });
  },
};

// --------------------------------------------------------------- documents

function checkFile(ctx: Ctx, a: Row): void {
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(String(a.p_mime_type))) ctx.fail('invalid_file_type: only PDF, JPEG, or PNG files are accepted');
  if (Number(a.p_file_size_bytes) > 10_485_760) ctx.fail('file_too_large: maximum file size is 10MB');
}

function safeName(name: unknown): string {
  return String(name).replace(/[^a-zA-Z0-9._-]/g, '_');
}

const documents: Record<string, RpcHandler> = {
  create_document_upload_slot: (a, ctx) => {
    const emp = row(ctx, 'employees', a.p_employee_id, 'employee');
    if (!(isOwnEmployee(ctx, emp.id) || can(ctx, MANAGE_EMP))) ctx.fail('insufficient_privilege: cannot upload a document for this employee', '42501', 403);
    checkFile(ctx, a);
    const id = ctx.backend.newId();
    const created = insert(ctx, 'employee_documents', {
      id, tenant_id: emp.tenant_id, employee_id: emp.id, document_type: a.p_document_type, file_name: a.p_file_name, mime_type: a.p_mime_type,
      file_size_bytes: a.p_file_size_bytes, storage_path: `${emp.tenant_id}/${emp.id}/${id}-${safeName(a.p_file_name)}`, version: 1,
      supersedes_document_id: null, status: 'uploaded', expiry_date: a.p_expiry_date ?? null, uploaded_by: ctx.session.userId,
      verified_by: null, verified_at: null, review_notes: null,
    });
    audit(ctx, emp.tenant_id, 'document_upload_slot_created', 'employee_documents', created.id);
    return created;
  },
  replace_document: (a, ctx) => {
    const old = row(ctx, 'employee_documents', a.p_old_document_id, 'document');
    if (!(isOwnEmployee(ctx, old.employee_id) || can(ctx, MANAGE_EMP))) ctx.fail('insufficient_privilege: cannot replace this document', '42501', 403);
    checkFile(ctx, a);
    if (old.status === 'archived') ctx.fail('invalid_transition: this version has already been replaced');
    touch(ctx, old, { status: 'archived', status_before_archive: old.status });
    const id = ctx.backend.newId();
    const created = insert(ctx, 'employee_documents', {
      id, tenant_id: old.tenant_id, employee_id: old.employee_id, document_type: old.document_type, file_name: a.p_file_name, mime_type: a.p_mime_type,
      file_size_bytes: a.p_file_size_bytes, storage_path: `${old.tenant_id}/${old.employee_id}/${id}-${safeName(a.p_file_name)}`, version: Number(old.version) + 1,
      supersedes_document_id: old.id, status: 'uploaded', expiry_date: a.p_expiry_date ?? old.expiry_date, uploaded_by: ctx.session.userId,
      verified_by: null, verified_at: null, review_notes: null,
    });
    audit(ctx, old.tenant_id, 'document_replaced', 'employee_documents', created.id);
    return created;
  },
  cancel_document_upload: (a, ctx) => {
    const d = row(ctx, 'employee_documents', a.p_document_id, 'document');
    if (d.uploaded_by !== ctx.session.userId) ctx.fail('insufficient_privilege: only the uploader can cancel an upload', '42501', 403);
    if (d.status !== 'uploaded' || d.verified_by) ctx.fail('invalid_transition: only a fresh, unreviewed upload can be cancelled');
    if (d.supersedes_document_id) {
      const prev = ctx.backend.table('employee_documents').find((x) => x.id === d.supersedes_document_id && x.status === 'archived');
      if (prev) touch(ctx, prev, { status: prev.status_before_archive ?? 'uploaded', status_before_archive: null });
    }
    ctx.backend.tables.set('employee_documents', ctx.backend.table('employee_documents').filter((x) => x !== d));
    audit(ctx, d.tenant_id, 'document_upload_cancelled', 'employee_documents', d.id);
    return null;
  },
  verify_document: (a, ctx) => {
    const d = row(ctx, 'employee_documents', a.p_document_id, 'document');
    require_(ctx, MANAGE_EMP, 'cannot verify documents for this tenant');
    sod(ctx, 'document.verify', [d.uploaded_by as string, employeeProfile(ctx, d.employee_id)]);
    if (!['uploaded', 'pending_review'].includes(String(d.status))) ctx.fail(`invalid_transition: cannot verify a ${d.status} document`);
    return touch(ctx, d, { status: a.p_approve ? 'verified' : 'rejected', verified_by: ctx.session.userId, verified_at: ctx.now, review_notes: a.p_review_notes ?? null });
  },
  sync_expired_documents: (_a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot sync documents for this tenant');
    const today = ctx.now.slice(0, 10);
    return ctx.backend.visible('employee_documents').filter((d) => d.status === 'verified' && d.expiry_date && String(d.expiry_date) < today).map((d) => touch(ctx, d, { status: 'expired' }));
  },
  create_contract_document_slot: (a, ctx) => {
    const contract = row(ctx, 'contracts', a.p_contract_id, 'contract');
    require_(ctx, ORG_STRUCT, 'cannot manage contract documents');
    checkFile(ctx, a);
    const id = ctx.backend.newId();
    return insert(ctx, 'contract_documents', {
      id, tenant_id: contract.tenant_id, contract_id: contract.id, file_name: a.p_file_name, mime_type: a.p_mime_type, file_size_bytes: a.p_file_size_bytes,
      storage_path: `${contract.tenant_id}/${contract.id}/${id}-${safeName(a.p_file_name)}`, uploaded_by: ctx.session.userId,
    });
  },
};

// --------------------------------------------------------------- incidents

const INCIDENT_NEXT: Record<string, string[]> = {
  reported: ['acknowledged'],
  acknowledged: ['investigating'],
  investigating: ['corrective_action'],
  corrective_action: ['pending_closure'],
  pending_closure: ['closed', 'investigating'],
  closed: ['investigating'],
};

const incidents: Record<string, RpcHandler> = {
  report_incident: (a, ctx) => {
    if (a.p_tenant_id !== ctx.session.tenantId && ctx.session.role !== 'platform_administrator') ctx.fail('insufficient_privilege: cannot report incidents for this tenant', '42501', 403);
    const n = ctx.backend.table('incidents').length + 1;
    const created = insert(ctx, 'incidents', {
      tenant_id: a.p_tenant_id, reference_number: `INC-2026-${String(n).padStart(6, '0')}`, site_id: a.p_site_id ?? null, contract_id: a.p_contract_id ?? null,
      category: a.p_category, severity: a.p_severity, status: 'reported', occurred_at: a.p_occurred_at, reported_by: ctx.session.userId, description: a.p_description,
      investigation_notes: null, corrective_action_summary: null, closed_by: null, closed_at: null,
    });
    audit(ctx, a.p_tenant_id, 'incident_reported', 'incidents', created.id);
    return created;
  },
  transition_incident_status: (a, ctx) => {
    const i = row(ctx, 'incidents', a.p_incident_id, 'incident');
    require_(ctx, MANAGE_OPS, 'cannot manage this incident');
    if (!(INCIDENT_NEXT[String(i.status)] ?? []).includes(String(a.p_new_status))) ctx.fail(`invalid_transition: cannot move incident from ${i.status} to ${a.p_new_status}`);
    if (a.p_new_status === 'closed') sod(ctx, 'incident.close', [i.reported_by as string]);
    audit(ctx, i.tenant_id, 'incident_status_changed', 'incidents', i.id);
    return touch(ctx, i, {
      status: a.p_new_status,
      investigation_notes: a.p_notes ?? i.investigation_notes,
      closed_by: a.p_new_status === 'closed' ? ctx.session.userId : null,
      closed_at: a.p_new_status === 'closed' ? ctx.now : null,
    });
  },
  add_incident_action: (a, ctx) => {
    const i = row(ctx, 'incidents', a.p_incident_id, 'incident');
    require_(ctx, MANAGE_OPS, 'cannot manage this incident');
    return insert(ctx, 'incident_actions', { tenant_id: i.tenant_id, incident_id: i.id, description: a.p_description, owner_profile_id: a.p_owner_profile_id ?? null, due_date: a.p_due_date ?? null, status: 'open', completed_at: null, verified_by: null, verified_at: null });
  },
  complete_incident_action: (a, ctx) => {
    const act = row(ctx, 'incident_actions', a.p_action_id, 'corrective action');
    if (!(act.owner_profile_id === ctx.session.userId || can(ctx, MANAGE_OPS))) ctx.fail('insufficient_privilege: cannot complete this action', '42501', 403);
    if (!['open', 'in_progress'].includes(String(act.status))) ctx.fail(`invalid_transition: cannot complete a ${act.status} action`);
    return touch(ctx, act, { status: 'completed', completed_at: ctx.now });
  },
  verify_incident_action: (a, ctx) => {
    const act = row(ctx, 'incident_actions', a.p_action_id, 'corrective action');
    require_(ctx, MANAGE_OPS, 'cannot verify actions');
    sod(ctx, 'incident_action.verify', [act.owner_profile_id as string]);
    if (act.status !== 'completed') ctx.fail(`invalid_transition: only a completed action can be verified (current status: ${act.status})`);
    return touch(ctx, act, { status: 'verified', verified_by: ctx.session.userId, verified_at: ctx.now });
  },
  link_incident_employee: (a, ctx) => {
    const i = row(ctx, 'incidents', a.p_incident_id, 'incident');
    require_(ctx, MANAGE_OPS, 'cannot manage this incident');
    return insert(ctx, 'incident_affected_employees', { tenant_id: i.tenant_id, incident_id: i.id, employee_id: a.p_employee_id, involvement: a.p_involvement ?? 'affected' });
  },
  upsert_compliance_record: (a, ctx) => {
    require_(ctx, MANAGE_OPS, 'cannot manage compliance records');
    const base = { site_id: a.p_site_id ?? null, client_id: a.p_client_id ?? null, contract_id: a.p_contract_id ?? null, responsible_profile_id: a.p_responsible_profile_id ?? null, due_date: a.p_due_date ?? null, expiry_date: a.p_expiry_date ?? null, evidence_storage_path: a.p_evidence_storage_path ?? null, notes: a.p_notes ?? null };
    if (a.p_id) return touch(ctx, row(ctx, 'compliance_records', a.p_id, 'compliance record'), base);
    return insert(ctx, 'compliance_records', { tenant_id: tenant(ctx), requirement_id: a.p_requirement_id, status: 'pending', completed_date: null, verified_by: null, verified_at: null, ...base });
  },
  verify_compliance_record: (a, ctx) => {
    const r = row(ctx, 'compliance_records', a.p_id, 'compliance record');
    require_(ctx, MANAGE_OPS, 'cannot verify compliance records');
    sod(ctx, 'compliance.verify', [r.responsible_profile_id as string]);
    return touch(ctx, r, { status: a.p_approve ? 'compliant' : 'non_compliant', verified_by: ctx.session.userId, verified_at: ctx.now, completed_date: a.p_approve ? ctx.now.slice(0, 10) : r.completed_date });
  },
};

// ------------------------------------------- procurement / inventory / assets

const PROCUREMENT_NEXT: Record<string, string[]> = { approved: ['ordered'], ordered: ['received'], received: ['completed'], requested: ['submitted', 'cancelled'], submitted: ['cancelled'] };

const SIGN: Record<string, number> = { receipt: 1, transfer_in: 1, return: 1, issue: -1, transfer_out: -1, adjustment: 1 };

function balance(ctx: Ctx, itemId: unknown, siteId: unknown): number {
  return ctx.backend.visible('inventory_movements').filter((m) => m.item_id === itemId && m.site_id === siteId).reduce((sum, m) => sum + Number(m.quantity) * (SIGN[String(m.movement_type)] ?? 1), 0);
}

const ASSET_NEXT: Record<string, string[]> = {
  available: ['assigned', 'maintenance', 'lost', 'damaged', 'retired'],
  assigned: ['available', 'maintenance', 'lost', 'damaged'],
  maintenance: ['available', 'retired'],
  damaged: ['maintenance', 'retired'],
  lost: ['retired', 'available'],
  retired: ['disposed'],
};

const operations: Record<string, RpcHandler> = {
  submit_procurement_request: (a, ctx) => {
    if (a.p_tenant_id !== ctx.session.tenantId && ctx.session.role !== 'platform_administrator') ctx.fail('insufficient_privilege: cannot submit for this tenant', '42501', 403);
    const created = insert(ctx, 'procurement_requests', { tenant_id: a.p_tenant_id, requested_by: ctx.session.userId, site_id: a.p_site_id ?? null, item_description: a.p_item_description, quantity: a.p_quantity, estimated_cost: a.p_estimated_cost ?? null, status: 'submitted', approved_by: null, approved_at: null, rejected_reason: null });
    audit(ctx, a.p_tenant_id, 'procurement_request_submitted', 'procurement_requests', created.id);
    return created;
  },
  decide_procurement_request: (a, ctx) => {
    const r = row(ctx, 'procurement_requests', a.p_request_id, 'procurement request');
    require_(ctx, MANAGE_OPS, 'cannot decide procurement requests');
    if (r.requested_by === ctx.session.userId && ctx.session.role !== 'platform_administrator') ctx.fail('insufficient_privilege: cannot approve your own procurement request', '42501', 403);
    if (r.status !== 'submitted') ctx.fail(`invalid_transition: cannot decide a ${r.status} request`);
    return touch(ctx, r, a.p_approve ? { status: 'approved', approved_by: ctx.session.userId, approved_at: ctx.now } : { status: 'rejected', rejected_reason: a.p_rejected_reason ?? null });
  },
  advance_procurement_request: (a, ctx) => {
    const r = row(ctx, 'procurement_requests', a.p_request_id, 'procurement request');
    require_(ctx, MANAGE_OPS, 'cannot advance procurement requests');
    if (!(PROCUREMENT_NEXT[String(r.status)] ?? []).includes(String(a.p_new_status))) ctx.fail(`invalid_transition: cannot move procurement request from ${r.status} to ${a.p_new_status}`);
    return touch(ctx, r, { status: a.p_new_status });
  },
  record_inventory_movement: (a, ctx) => {
    require_(ctx, MANAGE_OPS, 'cannot record inventory movements');
    row(ctx, 'inventory_items', a.p_item_id, 'inventory item');
    const delta = Number(a.p_quantity) * (SIGN[String(a.p_movement_type)] ?? 1);
    if (!a.p_allow_negative && delta < 0 && balance(ctx, a.p_item_id, a.p_site_id) + delta < 0) ctx.fail('insufficient_stock: movement would take stock below zero');
    const created = insert(ctx, 'inventory_movements', { tenant_id: tenant(ctx), item_id: a.p_item_id, site_id: a.p_site_id, movement_type: a.p_movement_type, quantity: a.p_quantity, reference: a.p_reference ?? null, performed_by: ctx.session.userId });
    audit(ctx, tenant(ctx), 'inventory_movement_recorded', 'inventory_movements', created.id);
    return created;
  },
  get_inventory_balance: (a, ctx) => balance(ctx, a.p_item_id, a.p_site_id),
  get_inventory_balances: (a, ctx) => {
    const itemIds = [...new Set(ctx.backend.visible('inventory_movements').filter((m) => m.site_id === a.p_site_id).map((m) => m.item_id))];
    return itemIds.map((item_id) => ({ item_id, balance: balance(ctx, item_id, a.p_site_id) }));
  },
  assign_asset: (a, ctx) => {
    const asset = row(ctx, 'assets', a.p_asset_id, 'asset');
    require_(ctx, MANAGE_OPS, 'cannot assign assets');
    if (asset.status !== 'available') ctx.fail(`invalid_transition: cannot move asset from ${asset.status} to assigned`);
    insert(ctx, 'asset_assignments', { tenant_id: asset.tenant_id, asset_id: asset.id, assigned_to_employee_id: a.p_assigned_to_employee_id ?? null, assigned_to_team_id: a.p_assigned_to_team_id ?? null, assigned_to_site_id: a.p_assigned_to_site_id ?? null, assigned_by: ctx.session.userId, assigned_at: ctx.now, returned_at: null, condition_at_assignment: a.p_condition ?? null, condition_at_return: null, reason: a.p_reason ?? null });
    audit(ctx, asset.tenant_id, 'asset_assigned', 'assets', asset.id);
    return touch(ctx, asset, { status: 'assigned', custodian_employee_id: a.p_assigned_to_employee_id ?? null });
  },
  return_asset: (a, ctx) => {
    const asset = row(ctx, 'assets', a.p_asset_id, 'asset');
    require_(ctx, MANAGE_OPS, 'cannot return assets');
    if (asset.status !== 'assigned') ctx.fail(`invalid_transition: cannot return a ${asset.status} asset`);
    const open = ctx.backend.table('asset_assignments').find((x) => x.asset_id === asset.id && !x.returned_at);
    if (open) touch(ctx, open, { returned_at: ctx.now, condition_at_return: a.p_condition_at_return ?? null });
    audit(ctx, asset.tenant_id, 'asset_returned', 'assets', asset.id);
    return touch(ctx, asset, { status: a.p_new_status ?? 'available', custodian_employee_id: null, condition: a.p_condition_at_return ?? asset.condition });
  },
  transition_asset_status: (a, ctx) => {
    const asset = row(ctx, 'assets', a.p_asset_id, 'asset');
    require_(ctx, MANAGE_OPS, 'cannot change asset status');
    if (!(ASSET_NEXT[String(asset.status)] ?? []).includes(String(a.p_new_status))) ctx.fail(`invalid_transition: cannot move asset from ${asset.status} to ${a.p_new_status}`);
    return touch(ctx, asset, { status: a.p_new_status });
  },
  record_asset_maintenance: (a, ctx) => {
    const asset = row(ctx, 'assets', a.p_asset_id, 'asset');
    require_(ctx, MANAGE_OPS, 'cannot record maintenance');
    return insert(ctx, 'asset_maintenance_records', { tenant_id: asset.tenant_id, asset_id: asset.id, description: a.p_description, cost: a.p_cost ?? null, performed_at: a.p_performed_at ?? ctx.now.slice(0, 10), performed_by: ctx.session.userId });
  },
};

// ------------------------------------------------- employees / users / dev

const people: Record<string, RpcHandler> = {
  terminate_employee: (a, ctx) => {
    const e = row(ctx, 'employees', a.p_employee_id, 'employee');
    require_(ctx, MANAGE_EMP, 'cannot manage employees for this organization');
    if (e.employment_status === 'terminated') ctx.fail('invalid_transition: employee is already terminated');
    audit(ctx, e.tenant_id, 'employee_terminated', 'employees', e.id);
    return touch(ctx, e, { employment_status: 'terminated', employment_end_date: a.p_termination_date });
  },
  reactivate_employee: (a, ctx) => {
    const e = row(ctx, 'employees', a.p_employee_id, 'employee');
    require_(ctx, MANAGE_EMP, 'cannot manage employees for this organization');
    if (e.employment_status !== 'terminated') ctx.fail('invalid_transition: only a terminated employee can be reactivated');
    return touch(ctx, e, { employment_status: 'active', employment_end_date: null });
  },
  provision_employee_login: (a, ctx) => {
    const e = row(ctx, 'employees', a.p_employee_id, 'employee');
    require_(ctx, MANAGE_EMP, 'cannot manage employees for this organization');
    if (e.profile_id) ctx.fail(`already_provisioned: employee ${e.id} already has a linked login`);
    if (!e.email) ctx.fail('missing_email: employee has no email on file to provision a login for');
    const userId = ctx.backend.newId();
    insert(ctx, 'profiles', { id: userId, tenant_id: e.tenant_id, first_name: e.first_name, last_name: e.last_name, email: e.email, phone: a.p_phone ?? null, avatar_url: null, role: a.p_role, status: 'active' });
    touch(ctx, e, { profile_id: userId });
    audit(ctx, e.tenant_id, 'employee_login_provisioned', 'employees', e.id);
    return [{ user_id: userId, temporary_password: 'Temp-Passw0rd-E2E!' }];
  },
  admin_create_user: (a, ctx) => {
    require_(ctx, [...MANAGE_EMP], 'cannot manage users for this organization');
    if (ctx.backend.table('profiles').some((p) => String(p.email).toLowerCase() === String(a.p_email).toLowerCase())) ctx.fail('email_taken: a user with this email already exists');
    if (a.p_role === 'platform_administrator' && ctx.session.role !== 'platform_administrator') ctx.fail('insufficient_privilege: cannot assign role platform_administrator', '42501', 403);
    const tenantId = (a.p_tenant_id as string | undefined) ?? ctx.session.tenantId;
    const userId = ctx.backend.newId();
    insert(ctx, 'profiles', { id: userId, tenant_id: tenantId, first_name: a.p_first_name, last_name: a.p_last_name, email: a.p_email, phone: a.p_phone || null, avatar_url: null, role: a.p_role, status: 'active' });
    audit(ctx, tenantId, 'user_created', 'profiles', userId);
    return [{ user_id: userId, temporary_password: 'Temp-Passw0rd-E2E!' }];
  },
  admin_set_user_status: (a, ctx) => {
    const p = row(ctx, 'profiles', a.p_user_id, 'profile');
    require_(ctx, MANAGE_EMP, "cannot manage this user's tenant");
    sod(ctx, 'user.status', [a.p_user_id as string]);
    const privileged = ['platform_administrator', 'organization_administrator'];
    if (privileged.includes(String(p.role)) && !privileged.includes(ctx.session.role)) ctx.fail('insufficient_privilege: cannot change the status of this user', '42501', 403);
    audit(ctx, p.tenant_id, 'user_status_changed', 'profiles', p.id);
    return touch(ctx, p, { status: a.p_status });
  },
  admin_update_user_role: (a, ctx) => {
    const p = row(ctx, 'profiles', a.p_user_id, 'profile');
    require_(ctx, MANAGE_EMP, "cannot manage this user's tenant");
    sod(ctx, 'role.assign', [a.p_user_id as string]);
    if (ctx.session.role !== 'organization_administrator' && ctx.session.role !== 'platform_administrator') ctx.fail(`insufficient_privilege: cannot assign role ${a.p_new_role}`, '42501', 403);
    if (a.p_new_role === 'platform_administrator' && ctx.session.role !== 'platform_administrator') ctx.fail(`insufficient_privilege: cannot assign role ${a.p_new_role}`, '42501', 403);
    touch(ctx, p, { role: a.p_new_role });
    audit(ctx, p.tenant_id, 'role_changed', 'profiles', p.id);
    return null;
  },
};

const development: Record<string, RpcHandler> = {
  set_employee_skill: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot manage skills');
    const existing = ctx.backend.table('employee_skills').find((s) => s.employee_id === a.p_employee_id && s.skill_id === a.p_skill_id);
    if (existing) return touch(ctx, existing, { proficiency_level: a.p_proficiency_level, verified_by: null, verified_at: null });
    return insert(ctx, 'employee_skills', { tenant_id: tenant(ctx), employee_id: a.p_employee_id, skill_id: a.p_skill_id, proficiency_level: a.p_proficiency_level, evidence_document_id: null, verified_by: null, verified_at: null });
  },
  verify_employee_skill: (a, ctx) => {
    const s = row(ctx, 'employee_skills', a.p_employee_skill_id, 'employee skill');
    require_(ctx, MANAGE_EMP, 'cannot verify skills');
    sod(ctx, 'skill.verify', [employeeProfile(ctx, s.employee_id)]);
    return touch(ctx, s, { verified_by: ctx.session.userId, verified_at: ctx.now });
  },
  enroll_employee_training: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot manage training');
    return insert(ctx, 'training_enrollments', { tenant_id: tenant(ctx), training_program_id: a.p_training_program_id, employee_id: a.p_employee_id, status: 'scheduled', enrolled_at: ctx.now, completed_at: null, result: null, resulting_qualification_id: null });
  },
  complete_employee_training: (a, ctx) => {
    const en = row(ctx, 'training_enrollments', a.p_enrollment_id, 'enrollment');
    require_(ctx, MANAGE_EMP, 'cannot manage training');
    return touch(ctx, en, { status: a.p_status, result: a.p_result ?? null, completed_at: ctx.now });
  },
  create_performance_review: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot manage performance reviews');
    return insert(ctx, 'performance_reviews', { tenant_id: tenant(ctx), employee_id: a.p_employee_id, reviewer_profile_id: a.p_reviewer_profile_id, review_period_start: a.p_review_period_start, review_period_end: a.p_review_period_end, status: 'draft', overall_rating: null, manager_comments: null, employee_comments: null, finalized_at: null });
  },
  advance_performance_review: (a, ctx) => {
    const r = row(ctx, 'performance_reviews', a.p_review_id, 'performance review');
    const order = ['draft', 'manager_review', 'employee_review', 'acknowledgement', 'finalized'];
    if (order.indexOf(String(a.p_new_status)) !== order.indexOf(String(r.status)) + 1) ctx.fail(`invalid_transition: cannot move performance review from ${r.status} to ${a.p_new_status}`);
    const isEmployee = isOwnEmployee(ctx, r.employee_id);
    if (a.p_new_status === 'finalized' || !isEmployee) require_(ctx, MANAGE_EMP, 'cannot manage performance reviews');
    return touch(ctx, r, { status: a.p_new_status, manager_comments: a.p_manager_comments ?? r.manager_comments, employee_comments: a.p_employee_comments ?? r.employee_comments, overall_rating: a.p_overall_rating ?? r.overall_rating, finalized_at: a.p_new_status === 'finalized' ? ctx.now : null });
  },
  add_development_action: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot manage development actions');
    return insert(ctx, 'development_actions', { tenant_id: tenant(ctx), employee_id: a.p_employee_id, review_id: a.p_review_id ?? null, goal: a.p_goal, owner_profile_id: a.p_owner_profile_id ?? null, target_date: a.p_target_date ?? null, status: 'open', completed_at: null });
  },
  update_development_action_status: (a, ctx) => {
    const d = row(ctx, 'development_actions', a.p_id, 'development action');
    return touch(ctx, d, { status: a.p_status, completed_at: a.p_status === 'completed' ? ctx.now : null });
  },
  upsert_employee_qualification: (a, ctx) => {
    require_(ctx, MANAGE_EMP, 'cannot manage qualifications');
    const data = { employee_id: a.p_employee_id, credential_type: a.p_credential_type, name: a.p_name, issuing_organization: a.p_issuing_organization ?? null, issue_date: a.p_issue_date ?? null, expiry_date: a.p_expiry_date ?? null, evidence_document_id: a.p_evidence_document_id ?? null };
    if (a.p_id) return touch(ctx, row(ctx, 'employee_qualifications', a.p_id, 'qualification'), data);
    return insert(ctx, 'employee_qualifications', { tenant_id: tenant(ctx), status: 'pending_verification', verified_by: null, verified_at: null, ...data });
  },
  verify_employee_qualification: (a, ctx) => {
    const q = row(ctx, 'employee_qualifications', a.p_id, 'qualification');
    require_(ctx, MANAGE_EMP, 'cannot verify qualifications');
    sod(ctx, 'qualification.verify', [employeeProfile(ctx, q.employee_id)]);
    return touch(ctx, q, { status: a.p_approve ? 'verified' : 'revoked', verified_by: ctx.session.userId, verified_at: ctx.now });
  },
};

// --------------------------------------------------------------- reporting

const reporting: Record<string, RpcHandler> = {
  get_operational_metrics: (_a, ctx) => {
    const b = ctx.backend;
    const active = b.visible('employees').filter((e) => e.employment_status === 'active').length;
    const records = b.visible('attendance_records');
    const counted = records.filter((r) => ['present', 'late', 'absent'].includes(String(r.status)));
    const attended = counted.filter((r) => r.status !== 'absent').length;
    const tasksAll = b.visible('tasks');
    const done = tasksAll.filter((t) => ['completed', 'verified'].includes(String(t.status))).length;
    const open = b.visible('incidents').filter((i) => i.status !== 'closed');
    const soon = new Date(Date.parse(ctx.now) + 30 * 86_400_000).toISOString().slice(0, 10);
    return [
      {
        active_employee_count: active,
        attendance_rate_pct: counted.length ? Math.round((attended / counted.length) * 1000) / 10 : 0,
        late_attendance_count: records.filter((r) => r.status === 'late').length,
        pending_leave_requests: b.visible('leave_requests').filter((r) => r.status === 'pending').length,
        approved_leave_days: b.visible('leave_requests').filter((r) => r.status === 'approved').reduce((s, r) => s + leaveDays(r), 0),
        task_completion_rate_pct: tasksAll.length ? Math.round((done / tasksAll.length) * 1000) / 10 : 0,
        overdue_task_count: tasksAll.filter((t) => ['open', 'in_progress', 'escalated'].includes(String(t.status)) && t.due_at && String(t.due_at) < ctx.now).length,
        open_incident_count: open.length,
        critical_incident_count: open.filter((i) => i.severity === 'critical').length,
        active_asset_count: b.visible('assets').filter((x) => !['retired', 'disposed'].includes(String(x.status))).length,
        assets_in_maintenance_count: b.visible('assets').filter((x) => x.status === 'maintenance').length,
        active_contract_count: b.visible('contracts').filter((c) => c.status === 'active').length,
        contracts_expiring_count: b.visible('contracts').filter((c) => c.status === 'active' && c.end_date && String(c.end_date) <= soon).length,
        qualifications_expiring_count: b.visible('employee_qualifications').filter((q) => q.expiry_date && String(q.expiry_date) <= soon).length,
        trainings_completed_count: b.visible('training_enrollments').filter((t) => t.status === 'completed').length,
      },
    ];
  },
  compute_sla_measurement: (a, ctx) => {
    const sla = row(ctx, 'sla_definitions', a.p_sla_definition_id, 'SLA definition');
    const all = ctx.backend.visible('tasks').filter((t) => !sla.site_id || t.site_id === sla.site_id);
    const done = all.filter((t) => ['completed', 'verified'].includes(String(t.status))).length;
    const actual = all.length ? Math.round((done / all.length) * 1000) / 10 : 0;
    return insert(ctx, 'sla_measurements', { tenant_id: sla.tenant_id, sla_definition_id: sla.id, period_start: a.p_period_start, period_end: a.p_period_end, actual_value: actual, is_met: actual >= Number(sla.target_value), computed_by: ctx.session.userId });
  },
};

export const defaultRpcHandlers: Record<string, RpcHandler> = {
  ...leave,
  ...attendance,
  ...tasks,
  ...documents,
  ...incidents,
  ...operations,
  ...people,
  ...development,
  ...reporting,
};
