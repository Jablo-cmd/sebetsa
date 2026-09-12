-- Sebetsa Phase I — Attendance RPCs.
--
-- Every privileged/self-service mutation to attendance_records/
-- attendance_breaks/attendance_corrections goes through one of these
-- SECURITY DEFINER functions — never a direct client write to the fields
-- that carry meaning (clock_in_at/clock_out_at/status/computed metrics).
-- Follows the exact shape established in Phase H (submit_leave_request et
-- al.): resolve tenant/employee server-side, permission-check, row-lock
-- before any status-dependent write, atomic, write_audit_log(), pinned
-- search_path, revoke from public/anon.

-- ---------------------------------------------------------------------------
-- compute_attendance_metrics: authoritative late/early/worked/overtime
-- calculation. Never trusted from the client — always derived here from
-- the shift (if any) and the tenant's attendance_policies (falling back to
-- 5/5/15 minutes if the tenant has no policy row).

create or replace function public.compute_attendance_metrics(p_attendance_record_id uuid)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_shift public.shifts;
  v_policy public.attendance_policies;
  v_grace int := 5;
  v_early_threshold int := 5;
  v_overtime_threshold int := 15;
  v_break_minutes numeric := 0;
  v_late_minutes int;
  v_early_minutes int;
  v_worked_minutes int;
  v_overtime_minutes int;
  v_new_status public.attendance_status;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id for update;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select * into v_policy from public.attendance_policies where tenant_id = v_record.tenant_id;
  if found then
    v_grace := v_policy.grace_period_minutes;
    v_early_threshold := v_policy.early_departure_threshold_minutes;
    v_overtime_threshold := v_policy.overtime_threshold_minutes;
  end if;

  if v_record.shift_id is not null then
    select * into v_shift from public.shifts where id = v_record.shift_id;
  end if;

  v_late_minutes := null;
  v_early_minutes := null;
  v_worked_minutes := null;
  v_overtime_minutes := null;
  v_new_status := v_record.status;

  if v_record.clock_in_at is not null and v_shift.id is not null then
    v_late_minutes := greatest(0, floor(extract(epoch from (v_record.clock_in_at - (v_shift.starts_at + make_interval(mins => v_grace)))) / 60))::int;
    if v_late_minutes = 0 then v_late_minutes := null; end if;
  end if;

  if v_record.clock_out_at is not null then
    select coalesce(sum(extract(epoch from (break_end - break_start))), 0) / 60 into v_break_minutes
    from public.attendance_breaks
    where attendance_record_id = p_attendance_record_id and break_end is not null;

    v_worked_minutes := greatest(0, floor(extract(epoch from (v_record.clock_out_at - v_record.clock_in_at)) / 60 - v_break_minutes))::int;

    if v_shift.id is not null then
      if v_record.clock_out_at < (v_shift.ends_at - make_interval(mins => v_early_threshold)) then
        v_early_minutes := floor(extract(epoch from ((v_shift.ends_at - make_interval(mins => v_early_threshold)) - v_record.clock_out_at)) / 60)::int;
      end if;
      if v_record.clock_out_at > (v_shift.ends_at + make_interval(mins => v_overtime_threshold)) then
        v_overtime_minutes := floor(extract(epoch from (v_record.clock_out_at - (v_shift.ends_at + make_interval(mins => v_overtime_threshold)))) / 60)::int;
      end if;
    end if;
  end if;

  -- Status is only auto-advanced out of 'unconfirmed' — a manager's
  -- explicit status (e.g. 'excused', or a correction-applied value) is
  -- never silently overwritten by this recomputation.
  if v_record.status = 'unconfirmed' and v_record.clock_in_at is not null then
    v_new_status := case when v_late_minutes is not null then 'late' else 'present' end;
  end if;

  update public.attendance_records
  set late_minutes = v_late_minutes,
      early_departure_minutes = v_early_minutes,
      worked_minutes = v_worked_minutes,
      overtime_minutes = v_overtime_minutes,
      status = v_new_status
  where id = p_attendance_record_id
  returning * into v_record;

  return v_record;
end;
$$;

comment on function public.compute_attendance_metrics(uuid) is
  'Authoritative late/early-departure/worked/overtime calculation from the linked shift + the tenant''s attendance_policies (falling back to 5/5/15 minutes). Called by clock_in/clock_out/end_break — never computed client-side.';

revoke execute on function public.compute_attendance_metrics(uuid) from public, anon;
grant execute on function public.compute_attendance_metrics(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- clock_in: self-service (own employee record) or manager-on-behalf.
-- Prevents the "multiple active clock-ins" impossible sequence via a
-- partial unique index (below) rather than relying on the check alone.

create unique index attendance_records_one_open_per_employee_idx
  on public.attendance_records (employee_id)
  where (clock_in_at is not null and clock_out_at is null);

comment on index public.attendance_records_one_open_per_employee_idx is
  'Database-enforced: an employee cannot have two open (clocked-in, not clocked-out) attendance records at once — mirrors shifts_no_overlap''s "constraint, not just application logic" approach.';

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

-- ---------------------------------------------------------------------------
-- clock_out: closes the open attendance record and computes final metrics.

create or replace function public.clock_out(p_attendance_record_id uuid)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id for update;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot clock out this attendance record';
  end if;

  if v_record.clock_in_at is null then
    raise exception 'invalid_sequence: cannot clock out before clocking in';
  end if;
  if v_record.clock_out_at is not null then
    raise exception 'invalid_sequence: already clocked out';
  end if;
  if exists (select 1 from public.attendance_breaks where attendance_record_id = p_attendance_record_id and break_end is null) then
    raise exception 'invalid_sequence: end the open break before clocking out';
  end if;

  update public.attendance_records set clock_out_at = now() where id = p_attendance_record_id;

  select * into v_record from public.compute_attendance_metrics(p_attendance_record_id);

  perform public.write_audit_log(v_record.tenant_id, auth.uid(), 'attendance_clock_out', 'attendance_records', v_record.id, null, jsonb_build_object('clock_out_at', v_record.clock_out_at, 'worked_minutes', v_record.worked_minutes));

  return v_record;
end;
$$;

revoke execute on function public.clock_out(uuid) from public, anon;
grant execute on function public.clock_out(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- start_break / end_break.

create or replace function public.start_break(p_attendance_record_id uuid)
returns public.attendance_breaks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
  v_result public.attendance_breaks;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id for update;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot manage breaks for this attendance record';
  end if;

  if v_record.clock_in_at is null or v_record.clock_out_at is not null then
    raise exception 'invalid_sequence: can only start a break while clocked in';
  end if;

  insert into public.attendance_breaks (tenant_id, attendance_record_id, break_start)
  values (v_record.tenant_id, p_attendance_record_id, now())
  returning * into v_result;

  return v_result;
exception
  when unique_violation then
    raise exception 'invalid_sequence: a break is already in progress for this attendance record';
end;
$$;

revoke execute on function public.start_break(uuid) from public, anon;
grant execute on function public.start_break(uuid) to authenticated;

create or replace function public.end_break(p_attendance_record_id uuid)
returns public.attendance_breaks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
  v_result public.attendance_breaks;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id for update;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot manage breaks for this attendance record';
  end if;

  update public.attendance_breaks
  set break_end = now()
  where attendance_record_id = p_attendance_record_id and break_end is null
  returning * into v_result;

  if not found then
    raise exception 'invalid_sequence: no open break to end for this attendance record';
  end if;

  -- Recompute worked_minutes only if already clocked out (mid-shift break
  -- ending doesn't yet have a final worked total to adjust).
  if v_record.clock_out_at is not null then
    perform public.compute_attendance_metrics(p_attendance_record_id);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.end_break(uuid) from public, anon;
grant execute on function public.end_break(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- request_attendance_correction / decide_attendance_correction.

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

-- ---------------------------------------------------------------------------
-- Leave integration: approved leave marks an EXISTING attendance record
-- 'excused' for that date — never force-creates one (attendance stays "a
-- separate fact from the schedule," per its own original migration
-- comment). Revoked leave does not automatically revert the status — a
-- manager who already relied on 'excused' should re-review, matching the
-- "never silently mutate history" principle for a status a human may have
-- since acted on.

-- attendance_records has no plain `date` column, so the leave-date-range
-- match happens via the linked shift's date, which is the only reliable
-- way to know which calendar date an unconfirmed/no-show row belongs to.
create or replace function public.leave_requests_sync_attendance_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update public.attendance_records ar
    set status = 'excused'
    from public.shifts s
    where ar.shift_id = s.id
      and ar.employee_id = new.employee_id
      and ar.status = 'unconfirmed'
      and s.starts_at::date between new.start_date and new.end_date;
  end if;
  return new;
end;
$$;

comment on function public.leave_requests_sync_attendance_status() is
  'On leave approval, marks any existing unconfirmed attendance_records row for a shift within the leave range as excused — never force-creates an attendance row, never overwrites a status a manager already set (present/late/absent all stay untouched), never reverts on revocation.';

create trigger leave_requests_sync_attendance_status_trigger
  after update on public.leave_requests
  for each row
  execute function public.leave_requests_sync_attendance_status();
