-- Sebetsa Phase H — Leave & Absence, migration 6 of 6.
--
-- SECURITY DEFINER RPCs for every privileged leave transition/balance
-- operation, plus the affected-shifts lookup and the scheduling-conflict
-- guard. Follows the exact shape of terminate_employee/reactivate_employee/
-- admin_update_user_role (20260911100700_audit_log.sql): resolve tenant
-- server-side, permission-check, row-lock before any status-dependent
-- write, atomic multi-table write, write_audit_log(), revoke from public.

create or replace function public.leave_request_duration_days(
  p_start_date date,
  p_end_date date,
  p_is_half_day boolean
)
returns numeric
language sql
immutable
as $$
  select case
    when p_is_half_day then 0.5
    else (p_end_date - p_start_date + 1)::numeric
  end
$$;

comment on function public.leave_request_duration_days(date, date, boolean) is
  'Authoritative calendar-day duration for one leave request — never trusted from the client. Half-day is always 0.5 regardless of date range (a half-day request always spans exactly one date).';

grant execute on function public.leave_request_duration_days(date, date, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- submit_leave_request: self-service or manager-on-behalf. Duration/notice
-- validation happens here once, not duplicated client-side and server-side
-- with room to disagree.

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

-- ---------------------------------------------------------------------------
-- cancel_leave_request: own pending request only. Row-locked so a
-- concurrent approval can't race a cancellation.

create or replace function public.cancel_leave_request(p_leave_request_id uuid)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.leave_requests;
  v_is_own boolean;
begin
  select * into v_row from public.leave_requests where id = p_leave_request_id for update;
  if not found then
    raise exception 'not_found: no leave request %', p_leave_request_id;
  end if;

  select exists(select 1 from public.employees where id = v_row.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_approve_leave(v_row.tenant_id)) then
    raise exception 'insufficient_privilege: cannot cancel this leave request';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'invalid_leave_status_transition: only a pending request can be cancelled (current status: %)', v_row.status;
  end if;

  update public.leave_requests set status = 'cancelled' where id = p_leave_request_id
  returning * into v_row;

  update public.leave_balances
  set pending = greatest(0, pending - public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day))
  where tenant_id = v_row.tenant_id and employee_id = v_row.employee_id and leave_type_id = v_row.leave_type_id
    and period_year = extract(year from v_row.start_date)::int;

  perform public.write_audit_log(
    v_row.tenant_id, auth.uid(), 'leave_cancelled', 'leave_requests', v_row.id,
    jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'cancelled')
  );

  return v_row;
end;
$$;

revoke execute on function public.cancel_leave_request(uuid) from public;
grant execute on function public.cancel_leave_request(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- approve_leave_request / reject_leave_request: leave.approve only.
-- Row-locked; re-checks status inside the lock so two concurrent approvers
-- can't both succeed (the second sees status already 'approved' post-lock
-- and raises, rather than double-writing a usage transaction).

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
begin
  select * into v_row from public.leave_requests where id = p_leave_request_id for update;
  if not found then
    raise exception 'not_found: no leave request %', p_leave_request_id;
  end if;

  if not public.can_approve_leave(v_row.tenant_id) then
    raise exception 'insufficient_privilege: cannot approve leave for this tenant';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'invalid_leave_status_transition: only a pending request can be approved (current status: %)', v_row.status;
  end if;

  v_days := public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day);
  v_period_year := extract(year from v_row.start_date)::int;

  update public.leave_requests set status = 'approved', decision_notes = p_decision_notes where id = p_leave_request_id
  returning * into v_row;

  insert into public.leave_balances (tenant_id, employee_id, leave_type_id, period_year)
  values (v_row.tenant_id, v_row.employee_id, v_row.leave_type_id, v_period_year)
  on conflict (tenant_id, employee_id, leave_type_id, period_year) do nothing;

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

-- ---------------------------------------------------------------------------
-- revoke_leave_request: leave.approve only. Reverses the usage transaction;
-- the availability trigger (migration 5) removes the generated exceptions
-- on the resulting approved -> revoked transition.

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

  if v_row.status <> 'approved' then
    raise exception 'invalid_leave_status_transition: only an approved request can be revoked (current status: %)', v_row.status;
  end if;

  v_days := public.leave_request_duration_days(v_row.start_date, v_row.end_date, v_row.is_half_day);
  v_period_year := extract(year from v_row.start_date)::int;

  update public.leave_requests set status = 'revoked', decision_notes = coalesce(p_decision_notes, v_row.decision_notes) where id = p_leave_request_id
  returning * into v_row;

  -- Idempotency: only reverse if a usage transaction for this exact
  -- request hasn't already been reversed (guards a retried/duplicate RPC
  -- call — the row lock above already prevents a concurrent second
  -- revoke, since a second caller would see status='revoked' and raise
  -- above before reaching here).
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

-- ---------------------------------------------------------------------------
-- adjust_leave_balance: leave.manage only. Every adjustment is a signed
-- ledger transaction — never a direct UPDATE of leave_balances.remaining
-- (which is a generated column and cannot be UPDATEd directly anyway).

create or replace function public.adjust_leave_balance(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_period_year int,
  p_amount numeric,
  p_note text default null
)
returns public.leave_balances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.leave_balances;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_leave(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot adjust leave balances for this tenant';
  end if;

  insert into public.leave_balances (tenant_id, employee_id, leave_type_id, period_year)
  values (v_tenant_id, p_employee_id, p_leave_type_id, p_period_year)
  on conflict (tenant_id, employee_id, leave_type_id, period_year) do nothing;

  update public.leave_balances
  set adjustment = adjustment + p_amount
  where tenant_id = v_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and period_year = p_period_year
  returning * into v_result;

  insert into public.leave_balance_transactions
    (tenant_id, employee_id, leave_type_id, period_year, transaction_type, amount, created_by)
  values
    (v_tenant_id, p_employee_id, p_leave_type_id, p_period_year, 'adjustment', p_amount, auth.uid());

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'leave_balance_adjusted', 'leave_balances', v_result.id,
    null, jsonb_build_object('amount', p_amount, 'note', p_note, 'period_year', p_period_year)
  );

  return v_result;
end;
$$;

revoke execute on function public.adjust_leave_balance(uuid, uuid, int, numeric, text) from public;
grant execute on function public.adjust_leave_balance(uuid, uuid, int, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- recompute_leave_balance: re-derive the snapshot from the ledger and
-- repair drift. leave.manage only. Audits the repair only if one occurred.

create or replace function public.recompute_leave_balance(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_period_year int
)
returns public.leave_balances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_before public.leave_balances;
  v_ledger_used numeric;
  v_ledger_adjustment numeric;
  v_ledger_opening numeric;
  v_ledger_accrued numeric;
  v_ledger_carry_over numeric;
  v_result public.leave_balances;
  v_changed boolean;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_leave(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot recompute leave balances for this tenant';
  end if;

  select * into v_before from public.leave_balances
  where tenant_id = v_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and period_year = p_period_year
  for update;

  select
    coalesce(sum(amount) filter (where transaction_type in ('usage', 'reversal')), 0),
    coalesce(sum(amount) filter (where transaction_type = 'adjustment'), 0),
    coalesce(sum(amount) filter (where transaction_type = 'opening'), 0),
    coalesce(sum(amount) filter (where transaction_type = 'accrual'), 0),
    coalesce(sum(amount) filter (where transaction_type = 'carry_over'), 0)
  into v_ledger_used, v_ledger_adjustment, v_ledger_opening, v_ledger_accrued, v_ledger_carry_over
  from public.leave_balance_transactions
  where employee_id = p_employee_id and leave_type_id = p_leave_type_id and period_year = p_period_year;

  -- usage/reversal are stored as +usage/-reversal; the snapshot's `used`
  -- column is a positive consumed total, so negate the signed ledger sum.
  v_ledger_used := -v_ledger_used;

  if not found then
    insert into public.leave_balances (tenant_id, employee_id, leave_type_id, period_year, opening_balance, accrued, used, adjustment, carried_over)
    values (v_tenant_id, p_employee_id, p_leave_type_id, p_period_year, v_ledger_opening, v_ledger_accrued, v_ledger_used, v_ledger_adjustment, v_ledger_carry_over)
    returning * into v_result;
    v_changed := true;
  else
    v_changed := (
      v_before.used is distinct from v_ledger_used
      or v_before.adjustment is distinct from v_ledger_adjustment
      or v_before.opening_balance is distinct from v_ledger_opening
      or v_before.accrued is distinct from v_ledger_accrued
      or v_before.carried_over is distinct from v_ledger_carry_over
    );

    update public.leave_balances
    set opening_balance = v_ledger_opening,
        accrued = v_ledger_accrued,
        used = v_ledger_used,
        adjustment = v_ledger_adjustment,
        carried_over = v_ledger_carry_over
    where id = v_before.id
    returning * into v_result;
  end if;

  if v_changed then
    perform public.write_audit_log(
      v_tenant_id, auth.uid(), 'leave_balance_recomputed', 'leave_balances', v_result.id,
      to_jsonb(v_before), to_jsonb(v_result)
    );
  end if;

  return v_result;
end;
$$;

revoke execute on function public.recompute_leave_balance(uuid, uuid, int) from public;
grant execute on function public.recompute_leave_balance(uuid, uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- get_leave_affected_shifts: read-only. Surfaces shifts overlapping an
-- employee's approved leave range for a supervisor to act on manually
-- (cancel/reassign/substitute) — never auto-modifies shifts itself.

create or replace function public.get_leave_affected_shifts(p_leave_request_id uuid)
returns setof public.shifts
language sql
stable
security definer
set search_path = public
as $$
  select s.*
  from public.shifts s
  join public.leave_requests lr on lr.id = p_leave_request_id
  where s.tenant_id = lr.tenant_id
    and s.employee_id = lr.employee_id
    and s.status <> 'cancelled'
    and tstzrange(s.starts_at, s.ends_at) && tstzrange(lr.start_date::timestamptz, (lr.end_date + 1)::timestamptz)
    and (public.can_view_leave_broad(lr.tenant_id) or exists (
      select 1 from public.employees e where e.id = lr.employee_id and e.profile_id = auth.uid()
    ))
$$;

comment on function public.get_leave_affected_shifts(uuid) is
  'Read-only: shifts overlapping a leave request''s date range for that employee. Does not modify shifts — a supervisor reviews the list and manually cancels/reassigns/substitutes (shift_substitutions), per the approved architecture''s no-silent-schedule-changes rule.';

revoke execute on function public.get_leave_affected_shifts(uuid) from public;
grant execute on function public.get_leave_affected_shifts(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Scheduling-conflict guard: blocked by default, explicit permissioned
-- override, always audited. Does NOT touch shifts_no_overlap (a different,
-- purely physical rule — see architecture §16/§56) and is NOT a hard
-- exclusion constraint, since an override must remain possible.

create or replace function public.shifts_leave_conflict_guard()
returns trigger
language plpgsql
as $$
declare
  v_conflict boolean;
  v_override boolean;
begin
  select exists (
    select 1 from public.employee_availability_exceptions eae
    where eae.employee_id = new.employee_id
      and eae.leave_request_id is not null
      and eae.is_available = false
      and eae.exception_date >= new.starts_at::date
      and eae.exception_date <= new.ends_at::date
  ) into v_conflict;

  if not v_conflict then
    return new;
  end if;

  v_override := coalesce(current_setting('app.override_leave_conflict', true), '') = 'true';

  if not v_override then
    raise exception 'leave_conflict: employee % has approved leave overlapping this shift; pass override_leave_conflict to proceed', new.employee_id;
  end if;

  if not public.can_approve_leave(new.tenant_id) then
    raise exception 'insufficient_privilege: overriding a leave conflict requires leave.approve';
  end if;

  perform public.write_audit_log(
    new.tenant_id, auth.uid(), 'leave_schedule_override', 'shifts', coalesce(new.id, gen_random_uuid()),
    null, jsonb_build_object('employee_id', new.employee_id, 'starts_at', new.starts_at, 'ends_at', new.ends_at)
  );

  return new;
end;
$$;

comment on function public.shifts_leave_conflict_guard() is
  'Blocks creating/moving a shift into an employee''s approved-leave range unless the caller has leave.approve AND sets app.override_leave_conflict=true for the session (mirrors the app.allow_role_change session-flag pattern in admin_update_user_role) — every override is audit-logged. Independent of shifts_no_overlap, which handles the unrelated physical double-booking rule and is never modified here.';

create trigger shifts_leave_conflict_guard_trigger
  before insert or update on public.shifts
  for each row
  execute function public.shifts_leave_conflict_guard();
