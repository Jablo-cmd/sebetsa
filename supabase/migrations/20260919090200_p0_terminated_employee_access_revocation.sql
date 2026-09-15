-- Sebetsa — P0 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, Critical finding C-3).
--
-- terminate_employee() (20260911100700_audit_log.sql) sets
-- employees.employment_status='terminated' and profiles.status='inactive',
-- but neither was ever actually checked by any RLS policy or RPC — a
-- terminated employee's session stayed fully valid and every self-service
-- RPC that resolves `employees.profile_id = auth.uid()` kept succeeding
-- indefinitely (clock_in, submit_leave_request,
-- request_attendance_correction, complete_task).
--
-- This adds one new helper, employee_can_self_serve(), and threads a guard
-- clause through the four RPCs that create new employee-initiated state
-- (start a shift, request leave, request a correction, complete a task).
-- The guard applies to BOTH the self-service path and the manager-
-- initiated path — a manager should not be able to clock in, submit leave
-- for, request a correction for, or complete a task on behalf of a
-- terminated/suspended employee either, not just the employee themselves.
--
-- Deliberately scoped to 'terminated' and 'suspended' only (not
-- 'on_leave') — the audit's own required regression categories are
-- "active employee / terminated employee / suspended employee /
-- reactivated employee" (docs/SEBETSA_PRODUCTION_CHECKLIST.md). Whether an
-- 'on_leave' employee clocking in should itself be blocked is a separate,
-- already-tracked business-rule question (leave/attendance contradiction
-- handling), not part of this access-revocation fix.
--
-- clock_out/start_break/end_break are deliberately NOT gated here: they
-- only ever close out an attendance_record that already exists (created
-- while the employee was still active, since clock_in is now gated) —
-- blocking them would strand an open record with no way to close it out
-- and grants no new access. reactivate_employee() already exists and
-- flips employment_status back to 'active', which is sufficient to
-- restore self-service access through this same guard with no further
-- change needed.

create or replace function public.employee_can_self_serve(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select employment_status not in ('terminated', 'suspended') from public.employees where id = p_employee_id),
    false
  )
$$;

comment on function public.employee_can_self_serve(uuid) is
  'False for a terminated/suspended employee (or a nonexistent one) — gates the RPCs that create new employee-initiated state (clock_in, submit_leave_request, request_attendance_correction, complete_task). SECURITY DEFINER so it gives a correct answer regardless of the caller''s own employees RLS visibility.';

-- ---------------------------------------------------------------------
-- clock_in
-- ---------------------------------------------------------------------

create or replace function public.clock_in(
  p_employee_id uuid,
  p_site_id uuid,
  p_shift_id uuid default null
)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_own boolean;
  v_result public.attendance_records;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  select exists(select 1 from public.employees where id = p_employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_tenant_id)) then
    raise exception 'insufficient_privilege: cannot clock in this employee';
  end if;

  if not public.employee_can_self_serve(p_employee_id) then
    raise exception 'inactive_employee: this employee is terminated or suspended and cannot clock in';
  end if;

  if not exists (select 1 from public.sites where id = p_site_id and tenant_id = v_tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', p_site_id, v_tenant_id;
  end if;

  if p_shift_id is not null and not exists (select 1 from public.shifts where id = p_shift_id and tenant_id = v_tenant_id and employee_id = p_employee_id) then
    raise exception 'not_found: shift % does not belong to this employee in this tenant', p_shift_id;
  end if;

  if exists (select 1 from public.attendance_records where employee_id = p_employee_id and clock_in_at is not null and clock_out_at is null) then
    raise exception 'already_clocked_in: this employee already has an open attendance record';
  end if;

  insert into public.attendance_records (tenant_id, shift_id, site_id, employee_id, status, clock_in_at, recorded_by)
  values (v_tenant_id, p_shift_id, p_site_id, p_employee_id, 'unconfirmed', now(), auth.uid())
  returning * into v_result;

  select * into v_result from public.compute_attendance_metrics(v_result.id);

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'attendance_clock_in', 'attendance_records', v_result.id, null, jsonb_build_object('clock_in_at', v_result.clock_in_at, 'status', v_result.status));

  return v_result;
end;
$$;

revoke execute on function public.clock_in(uuid, uuid, uuid) from public, anon;
grant execute on function public.clock_in(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- submit_leave_request
-- ---------------------------------------------------------------------

create or replace function public.submit_leave_request(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_start_date date,
  p_end_date date,
  p_is_half_day boolean default false,
  p_half_day_period text default null,
  p_reason text default null,
  p_supporting_document_ref text default null
)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_own boolean;
  v_policy public.leave_policies;
  v_result public.leave_requests;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  select exists(select 1 from public.employees where id = p_employee_id and profile_id = auth.uid()) into v_is_own;

  if not (v_is_own or public.can_approve_leave(v_tenant_id)) then
    raise exception 'insufficient_privilege: cannot submit leave for this employee';
  end if;

  if not public.employee_can_self_serve(p_employee_id) then
    raise exception 'inactive_employee: this employee is terminated or suspended and cannot submit a leave request';
  end if;

  if p_end_date < p_start_date then
    raise exception 'invalid_date_range: end_date must not be before start_date';
  end if;

  if p_is_half_day and p_end_date <> p_start_date then
    raise exception 'invalid_half_day: a half-day request must have start_date = end_date';
  end if;

  select * into v_policy from public.leave_policies where tenant_id = v_tenant_id and leave_type_id = p_leave_type_id;
  if found and v_policy.min_notice_days > 0 and p_start_date < current_date + v_policy.min_notice_days then
    raise exception 'insufficient_notice: this leave type requires at least % day(s) notice', v_policy.min_notice_days;
  end if;
  if found and v_policy.requires_documentation and p_supporting_document_ref is null then
    raise exception 'documentation_required: this leave type requires supporting documentation';
  end if;
  if found and v_policy.max_consecutive_days is not null
     and public.leave_request_duration_days(p_start_date, p_end_date, p_is_half_day) > v_policy.max_consecutive_days then
    raise exception 'exceeds_max_consecutive_days: this leave type allows at most % consecutive day(s)', v_policy.max_consecutive_days;
  end if;

  insert into public.leave_requests (
    tenant_id, employee_id, leave_type_id, start_date, end_date,
    is_half_day, half_day_period, reason, supporting_document_ref
  ) values (
    v_tenant_id, p_employee_id, p_leave_type_id, p_start_date, p_end_date,
    p_is_half_day, p_half_day_period, p_reason, p_supporting_document_ref
  )
  returning * into v_result;

  update public.leave_balances
  set pending = pending + public.leave_request_duration_days(p_start_date, p_end_date, p_is_half_day)
  where tenant_id = v_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id
    and period_year = extract(year from p_start_date)::int;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'leave_requested', 'leave_requests', v_result.id,
    null, jsonb_build_object('status', 'pending', 'start_date', p_start_date, 'end_date', p_end_date)
  );

  return v_result;
end;
$$;

revoke execute on function public.submit_leave_request(uuid, uuid, date, date, boolean, text, text, text) from public;
grant execute on function public.submit_leave_request(uuid, uuid, date, date, boolean, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- request_attendance_correction
-- ---------------------------------------------------------------------

create or replace function public.request_attendance_correction(
  p_attendance_record_id uuid,
  p_field public.attendance_correction_field,
  p_new_value text,
  p_reason text
)
returns public.attendance_corrections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
  v_previous text;
  v_result public.attendance_corrections;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot request a correction for this attendance record';
  end if;

  if not public.employee_can_self_serve(v_record.employee_id) then
    raise exception 'inactive_employee: this employee is terminated or suspended and cannot request an attendance correction';
  end if;

  v_previous := case p_field
    when 'clock_in_at' then v_record.clock_in_at::text
    when 'clock_out_at' then v_record.clock_out_at::text
    when 'status' then v_record.status::text
  end;

  insert into public.attendance_corrections (tenant_id, attendance_record_id, field, previous_value, new_value, reason, requested_by)
  values (v_record.tenant_id, p_attendance_record_id, p_field, v_previous, p_new_value, p_reason, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(v_record.tenant_id, auth.uid(), 'attendance_correction_requested', 'attendance_corrections', v_result.id, null, jsonb_build_object('field', p_field, 'new_value', p_new_value));

  return v_result;
end;
$$;

revoke execute on function public.request_attendance_correction(uuid, public.attendance_correction_field, text, text) from public, anon;
grant execute on function public.request_attendance_correction(uuid, public.attendance_correction_field, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- complete_task
-- ---------------------------------------------------------------------

create or replace function public.complete_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks;
  v_is_assignee boolean;
  v_incomplete_count int;
  v_evidence_count int;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found then
    raise exception 'not_found: no task %', p_task_id;
  end if;

  select exists(select 1 from public.employees where id = v_task.assignee_id and profile_id = auth.uid()) into v_is_assignee;
  if not (v_is_assignee or public.can_manage_operations(v_task.tenant_id)) then
    raise exception 'insufficient_privilege: cannot complete this task';
  end if;

  if v_task.assignee_id is not null and not public.employee_can_self_serve(v_task.assignee_id) then
    raise exception 'inactive_employee: the assigned employee is terminated or suspended and this task cannot be completed on their behalf';
  end if;

  if v_task.status not in ('open', 'in_progress', 'escalated') then
    raise exception 'invalid_task_status_transition: only an open/in_progress/escalated task can be completed (current status: %)', v_task.status;
  end if;

  select count(*) into v_incomplete_count from public.task_checklist_items where task_id = p_task_id and not is_completed;
  if v_incomplete_count > 0 then
    raise exception 'checklist_incomplete: % checklist item(s) still incomplete', v_incomplete_count;
  end if;

  if v_task.requires_evidence then
    select count(*) into v_evidence_count from public.task_evidence where task_id = p_task_id;
    if v_evidence_count = 0 then
      raise exception 'evidence_required: this task requires at least one evidence entry before it can be completed';
    end if;
  end if;

  update public.tasks set status = 'in_progress' where id = p_task_id and status = 'open';
  update public.tasks set status = 'completed' where id = p_task_id
  returning * into v_task;

  perform public.write_audit_log(v_task.tenant_id, auth.uid(), 'task_completed', 'tasks', v_task.id, null, jsonb_build_object('status', 'completed'));

  return v_task;
end;
$$;

revoke execute on function public.complete_task(uuid) from public, anon;
grant execute on function public.complete_task(uuid) to authenticated;
