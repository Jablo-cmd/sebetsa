-- Sebetsa — P1 remediation (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining
-- Risks" #3): submit_leave_request()'s balance write was a plain UPDATE
-- with no upsert, so an employee's first-ever leave request for a given
-- leave_type/period_year — when no leave_balances row has ever been
-- created yet for that combination (nothing seeds one automatically; a
-- row only exists once someone has called adjust_leave_balance(),
-- recompute_leave_balance(), or approve_leave_request()'s own
-- insert-on-conflict) — silently affected zero rows. The request itself
-- still succeeded; only the "pending" figure was lost, with no error
-- surfaced anywhere.
--
-- Root cause, not a symptom: the UPDATE assumed a leave_balances row
-- always already exists, which was never actually guaranteed. Fixed the
-- same way approve_leave_request() (20260919090400) already established
-- for this exact table: INSERT ... ON CONFLICT (the table's own unique
-- constraint) DO UPDATE, so the row is created with the correct pending
-- figure if absent, or incremented if present — never silently skipped.
--
-- This does not change the intended business workflow: two separate
-- pending requests against the same employee/leave_type/period_year
-- correctly sum their pending days (this was already the intended
-- behavior of the plain UPDATE when a row existed — only the "no row yet"
-- case was broken); reject_leave_request/revoke_leave_request are
-- unaffected (submit's upsert now guarantees the row a reject's later
-- plain UPDATE needs already exists, so no other function needed to
-- change). All other checks (terminated-employee, tenant derivation,
-- date-range/half-day/policy validation) are copied unchanged from the
-- currently-active version of this function
-- (20260919090200_p0_terminated_employee_access_revocation.sql).

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
  v_days numeric;
  v_period_year int;
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

  v_days := public.leave_request_duration_days(p_start_date, p_end_date, p_is_half_day);
  v_period_year := extract(year from p_start_date)::int;

  insert into public.leave_balances (tenant_id, employee_id, leave_type_id, period_year, pending)
  values (v_tenant_id, p_employee_id, p_leave_type_id, v_period_year, v_days)
  on conflict (tenant_id, employee_id, leave_type_id, period_year)
  do update set pending = public.leave_balances.pending + excluded.pending;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'leave_requested', 'leave_requests', v_result.id,
    null, jsonb_build_object('status', 'pending', 'start_date', p_start_date, 'end_date', p_end_date)
  );

  return v_result;
end;
$$;
