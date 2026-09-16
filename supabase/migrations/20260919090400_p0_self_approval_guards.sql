-- Sebetsa — P0 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, High findings: self-approval /
-- separation-of-duties missing across leave, attendance-correction, task,
-- compliance and incident-action RPCs).
--
-- decide_procurement_request() (20260915090100_procurement_inventory_asset_rpcs.sql)
-- already does this correctly:
--   if v_requested_by = auth.uid() and not public.is_platform_admin() then
--     raise exception 'insufficient_privilege: cannot approve your own procurement request';
--   end if;
-- That exact pattern is replicated below into the seven RPCs the audit
-- found missing it. platform_administrator is deliberately exempted, same
-- as procurement's own precedent (a platform admin's cross-tenant/cross-
-- role reach is a separate, already-audited, already-logged bypass, not a
-- same-person approval loophole).
--
-- Also folds in the directly-related, already-scoped-for-this-function
-- fix for approve_leave_request never checking the request against
-- leave_balances.remaining before approving (High finding, same file
-- being touched anyway) — a request can no longer be approved for more
-- days than the employee's current remaining balance.

-- ---------------------------------------------------------------------
-- Leave: approve / reject / revoke, self-approval guard.
-- ---------------------------------------------------------------------

create or replace function public.approve_leave_request(p_leave_request_id uuid, p_decision_notes text default null)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.leave_requests;
  v_days numeric;
  v_period_year int;
  v_remaining numeric;
begin
  select * into v_row from public.leave_requests where id = p_leave_request_id for update;
  if not found then
    raise exception 'not_found: no leave request %', p_leave_request_id;
  end if;

  if not public.can_approve_leave(v_row.tenant_id) then
    raise exception 'insufficient_privilege: cannot approve leave for this tenant';
  end if;

  if exists (select 1 from public.employees where id = v_row.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot approve your own leave request';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'invalid_leave_status_transition: only a pending request can be approved (current status: %)', v_row.status;
  end if;

  v_days := public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day);
  v_period_year := extract(year from v_row.start_date)::int;

  insert into public.leave_balances (tenant_id, employee_id, leave_type_id, period_year)
  values (v_row.tenant_id, v_row.employee_id, v_row.leave_type_id, v_period_year)
  on conflict (tenant_id, employee_id, leave_type_id, period_year) do nothing;

  select remaining into v_remaining from public.leave_balances
  where tenant_id = v_row.tenant_id and employee_id = v_row.employee_id and leave_type_id = v_row.leave_type_id
    and period_year = v_period_year;

  if v_days > v_remaining then
    raise exception 'insufficient_balance: this request is for % day(s) but only % remain', v_days, v_remaining;
  end if;

  update public.leave_requests set status = 'approved', decision_notes = p_decision_notes where id = p_leave_request_id
  returning * into v_row;

  update public.leave_balances
  set used = used + v_days,
      pending = greatest(0, pending - v_days)
  where tenant_id = v_row.tenant_id and employee_id = v_row.employee_id and leave_type_id = v_row.leave_type_id
    and period_year = v_period_year;

  insert into public.leave_balance_transactions
    (tenant_id, employee_id, leave_type_id, period_year, transaction_type, amount, leave_request_id, created_by)
  values
    (v_row.tenant_id, v_row.employee_id, v_row.leave_type_id, v_period_year, 'usage', v_days, v_row.id, auth.uid());

  perform public.write_audit_log(
    v_row.tenant_id, auth.uid(), 'leave_approved', 'leave_requests', v_row.id,
    jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'approved', 'decision_notes', p_decision_notes)
  );

  return v_row;
end;
$$;

revoke execute on function public.approve_leave_request(uuid, text) from public;
grant execute on function public.approve_leave_request(uuid, text) to authenticated;

create or replace function public.reject_leave_request(p_leave_request_id uuid, p_decision_notes text default null)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.leave_requests;
  v_days numeric;
  v_period_year int;
begin
  select * into v_row from public.leave_requests where id = p_leave_request_id for update;
  if not found then
    raise exception 'not_found: no leave request %', p_leave_request_id;
  end if;

  if not public.can_approve_leave(v_row.tenant_id) then
    raise exception 'insufficient_privilege: cannot reject leave for this tenant';
  end if;

  if exists (select 1 from public.employees where id = v_row.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot reject your own leave request';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'invalid_leave_status_transition: only a pending request can be rejected (current status: %)', v_row.status;
  end if;

  v_days := public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day);
  v_period_year := extract(year from v_row.start_date)::int;

  update public.leave_requests set status = 'rejected', decision_notes = p_decision_notes where id = p_leave_request_id
  returning * into v_row;

  update public.leave_balances
  set pending = greatest(0, pending - v_days)
  where tenant_id = v_row.tenant_id and employee_id = v_row.employee_id and leave_type_id = v_row.leave_type_id
    and period_year = v_period_year;

  perform public.write_audit_log(
    v_row.tenant_id, auth.uid(), 'leave_rejected', 'leave_requests', v_row.id,
    jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'rejected', 'decision_notes', p_decision_notes)
  );

  return v_row;
end;
$$;

revoke execute on function public.reject_leave_request(uuid, text) from public;
grant execute on function public.reject_leave_request(uuid, text) to authenticated;

create or replace function public.revoke_leave_request(p_leave_request_id uuid, p_decision_notes text default null)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.leave_requests;
  v_days numeric;
  v_period_year int;
begin
  select * into v_row from public.leave_requests where id = p_leave_request_id for update;
  if not found then
    raise exception 'not_found: no leave request %', p_leave_request_id;
  end if;

  if not public.can_approve_leave(v_row.tenant_id) then
    raise exception 'insufficient_privilege: cannot revoke leave for this tenant';
  end if;

  if exists (select 1 from public.employees where id = v_row.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot revoke your own leave request';
  end if;

  if v_row.status <> 'approved' then
    raise exception 'invalid_leave_status_transition: only an approved request can be revoked (current status: %)', v_row.status;
  end if;

  v_days := public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day);
  v_period_year := extract(year from v_row.start_date)::int;

  update public.leave_requests set status = 'revoked', decision_notes = coalesce(p_decision_notes, v_row.decision_notes) where id = p_leave_request_id
  returning * into v_row;

  if not exists (
    select 1 from public.leave_balance_transactions
    where leave_request_id = v_row.id and transaction_type = 'reversal'
  ) then
    update public.leave_balances
    set used = greatest(0, used - v_days)
    where tenant_id = v_row.tenant_id and employee_id = v_row.employee_id and leave_type_id = v_row.leave_type_id
      and period_year = v_period_year;

    insert into public.leave_balance_transactions
      (tenant_id, employee_id, leave_type_id, period_year, transaction_type, amount, leave_request_id, created_by)
    values
      (v_row.tenant_id, v_row.employee_id, v_row.leave_type_id, v_period_year, 'reversal', -v_days, v_row.id, auth.uid());
  end if;

  perform public.write_audit_log(
    v_row.tenant_id, auth.uid(), 'leave_revoked', 'leave_requests', v_row.id,
    jsonb_build_object('status', 'approved'), jsonb_build_object('status', 'revoked', 'decision_notes', p_decision_notes)
  );

  return v_row;
end;
$$;

revoke execute on function public.revoke_leave_request(uuid, text) from public;
grant execute on function public.revoke_leave_request(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Attendance corrections: reviewer must differ from requester.
-- ---------------------------------------------------------------------

create or replace function public.decide_attendance_correction(
  p_correction_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns public.attendance_corrections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correction public.attendance_corrections;
begin
  select * into v_correction from public.attendance_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'not_found: no attendance correction %', p_correction_id;
  end if;

  if not public.can_manage_operations(v_correction.tenant_id) then
    raise exception 'insufficient_privilege: cannot decide attendance corrections for this tenant';
  end if;

  if v_correction.requested_by = auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot decide your own attendance correction request';
  end if;

  if v_correction.status <> 'pending' then
    raise exception 'invalid_transition: only a pending correction can be decided (current status: %)', v_correction.status;
  end if;

  update public.attendance_corrections
  set status = case when p_approve then 'approved' else 'rejected' end::public.attendance_correction_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_notes = p_review_notes
  where id = p_correction_id
  returning * into v_correction;

  if p_approve then
    if v_correction.field = 'clock_in_at' then
      update public.attendance_records set clock_in_at = v_correction.new_value::timestamptz where id = v_correction.attendance_record_id;
    elsif v_correction.field = 'clock_out_at' then
      update public.attendance_records set clock_out_at = v_correction.new_value::timestamptz where id = v_correction.attendance_record_id;
    elsif v_correction.field = 'status' then
      update public.attendance_records set status = v_correction.new_value::public.attendance_status where id = v_correction.attendance_record_id;
    end if;

    perform public.compute_attendance_metrics(v_correction.attendance_record_id);
  end if;

  perform public.write_audit_log(
    v_correction.tenant_id, auth.uid(), case when p_approve then 'attendance_correction_approved' else 'attendance_correction_rejected' end,
    'attendance_corrections', v_correction.id, null, jsonb_build_object('field', v_correction.field, 'new_value', v_correction.new_value, 'review_notes', p_review_notes)
  );

  return v_correction;
end;
$$;

revoke execute on function public.decide_attendance_correction(uuid, boolean, text) from public, anon;
grant execute on function public.decide_attendance_correction(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------
-- Tasks: verifier must differ from whoever completed it.
-- ---------------------------------------------------------------------

create or replace function public.verify_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found then
    raise exception 'not_found: no task %', p_task_id;
  end if;

  if not public.can_manage_operations(v_task.tenant_id) then
    raise exception 'insufficient_privilege: cannot verify tasks for this tenant';
  end if;

  if v_task.completed_by = auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot verify a task you completed yourself';
  end if;

  if v_task.status <> 'completed' then
    raise exception 'invalid_task_status_transition: only a completed task can be verified (current status: %)', v_task.status;
  end if;

  update public.tasks set status = 'verified' where id = p_task_id returning * into v_task;

  perform public.write_audit_log(v_task.tenant_id, auth.uid(), 'task_verified', 'tasks', v_task.id, null, null);

  return v_task;
end;
$$;

revoke execute on function public.verify_task(uuid) from public, anon;
grant execute on function public.verify_task(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Compliance records: verifier must differ from the responsible person.
-- Corrects the migration comment in 20260914090000_compliance_safety_incidents.sql
-- (lines ~295-297) which claimed this was already enforced — it was not.
-- ---------------------------------------------------------------------

create or replace function public.verify_compliance_record(p_id uuid, p_approve boolean)
returns public.compliance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_old_status public.compliance_status;
  v_responsible_profile_id uuid;
  v_result public.compliance_records;
begin
  select tenant_id, status, responsible_profile_id into v_tenant_id, v_old_status, v_responsible_profile_id
  from public.compliance_records where id = p_id
  for update;

  if not found then
    raise exception 'not_found: no compliance record %', p_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify compliance records for this tenant';
  end if;

  if v_responsible_profile_id = auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot verify your own compliance record';
  end if;

  update public.compliance_records
    set status = case when p_approve then 'compliant'::public.compliance_status else 'non_compliant'::public.compliance_status end,
        verified_by = auth.uid(),
        verified_at = now(),
        completed_date = case when p_approve then current_date else completed_date end
    where id = p_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'compliance_record_verified', 'compliance_records', p_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', v_result.status)
  );

  return v_result;
end;
$$;

revoke execute on function public.verify_compliance_record(uuid, boolean) from public, anon;
grant execute on function public.verify_compliance_record(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- Incident actions: verifier must differ from the action owner.
-- ---------------------------------------------------------------------

create or replace function public.verify_incident_action(p_action_id uuid)
returns public.incident_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_status public.incident_action_status;
  v_owner_profile_id uuid;
  v_result public.incident_actions;
begin
  select tenant_id, status, owner_profile_id into v_tenant_id, v_status, v_owner_profile_id
  from public.incident_actions where id = p_action_id
  for update;

  if not found then
    raise exception 'not_found: no incident action %', p_action_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify this action';
  end if;

  if v_owner_profile_id = auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot verify an action you own';
  end if;

  if v_status <> 'completed' then
    raise exception 'invalid_transition: action must be completed before it can be verified (currently %)', v_status;
  end if;

  update public.incident_actions
    set status = 'verified', verified_by = auth.uid(), verified_at = now()
    where id = p_action_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'incident_action_verified', 'incident_actions', p_action_id, jsonb_build_object('status', 'completed'), jsonb_build_object('status', 'verified'));

  return v_result;
end;
$$;

revoke execute on function public.verify_incident_action(uuid) from public, anon;
grant execute on function public.verify_incident_action(uuid) to authenticated;
