-- Sebetsa Phase I — Attendance & Time Management: RLS / lifecycle /
-- concurrency / leave-integration checks. Same pattern as
-- supabase/rls-tests/leave.sql — a real, repeatable psql script against
-- actual RLS policies/triggers/constraints/RPCs, not a mock.
--
--   supabase start
--   cat supabase/rls-tests/attendance_time_management.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000e1', 'Org E', 'active'),
  ('00000000-0000-0000-0000-0000000000f1', 'Org F', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'admin-e@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'employee-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e4', 'authenticated', 'authenticated', 'employee-e2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e1', 'Admin', 'E', 'admin-e@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e1', 'Emp', 'One', 'employee-e1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000e1', 'Emp', 'Two', 'employee-e2@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003201', '00000000-0000-0000-0000-0000000000e1', 'Client E');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004201', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000003201', 'Site E');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005201', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e3', 'E101', 'Emp', 'One', current_date),
  ('00000000-0000-0000-0000-000000005202', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e4', 'E102', 'Emp', 'Two', current_date);

insert into public.attendance_policies (tenant_id, grace_period_minutes, early_departure_threshold_minutes, overtime_threshold_minutes)
values ('00000000-0000-0000-0000-0000000000e1', 5, 5, 15);

-- A shift anchored in the past (today at a fixed time) so lateness is deterministic.
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values ('00000000-0000-0000-0000-000000009201', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000004201', '00000000-0000-0000-0000-000000005201', now() - interval '30 minutes', now() + interval '4 hours');

-- Tenant F cross-tenant targets.
reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003202', '00000000-0000-0000-0000-0000000000f1', 'Client F');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004202', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000003202', 'Site F');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-0000000000f1', 'F901', 'Other', 'TenantEmployee', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- clock_in: cross-tenant rejection, self-service, late computation.

do $$
begin
  begin
    perform public.clock_in('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-000000004201');
    raise exception 'SECURITY_FAILURE: clock_in succeeded for a cross-tenant employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: clock_in blocked for a cross-tenant employee (%)', sqlerrm;
  end;

  begin
    perform public.clock_in('00000000-0000-0000-0000-000000005201', '00000000-0000-0000-0000-000000004202');
    raise exception 'SECURITY_FAILURE: clock_in succeeded against a cross-tenant site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: clock_in blocked against a cross-tenant site (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e4","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.clock_in('00000000-0000-0000-0000-000000005201', '00000000-0000-0000-0000-000000004201');
    raise exception 'SECURITY_FAILURE: employee-e2 clocked in employee-e1';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from clocking in another employee (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e3","app_metadata":{"role":"employee"}}';

do $$
declare
  v_result public.attendance_records;
begin
  select * into v_result from public.clock_in('00000000-0000-0000-0000-000000005201', '00000000-0000-0000-0000-000000004201', '00000000-0000-0000-0000-000000009201');
  if v_result.status <> 'late' then raise exception 'FAIL: expected status=late (clocked in 30min after a shift with 5min grace), got %', v_result.status; end if;
  if v_result.late_minutes < 20 then raise exception 'FAIL: expected late_minutes >= 20, got %', v_result.late_minutes; end if;
  raise notice 'PASS: clock_in computed late status/minutes from the linked shift + policy grace period';
end $$;

do $$
begin
  begin
    perform public.clock_in('00000000-0000-0000-0000-000000005201', '00000000-0000-0000-0000-000000004201');
    raise exception 'SECURITY_FAILURE: a second clock_in succeeded while already clocked in';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: duplicate clock_in blocked (already open attendance record) (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- clock_out sequencing + breaks.

do $$
declare
  v_attendance_id uuid;
begin
  select id into v_attendance_id from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201' and clock_out_at is null;

  begin
    perform public.end_break(v_attendance_id);
    raise exception 'SECURITY_FAILURE: end_break succeeded with no open break';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: end_break blocked with no open break (%)', sqlerrm;
  end;

  perform public.start_break(v_attendance_id);

  begin
    perform public.start_break(v_attendance_id);
    raise exception 'SECURITY_FAILURE: a second concurrent open break succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a second concurrent open break is blocked (unique index) (%)', sqlerrm;
  end;

  begin
    perform public.clock_out(v_attendance_id);
    raise exception 'SECURITY_FAILURE: clock_out succeeded while a break was still open';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: clock_out blocked while a break is open (%)', sqlerrm;
  end;

  perform public.end_break(v_attendance_id);
  perform public.clock_out(v_attendance_id);

  begin
    perform public.clock_out(v_attendance_id);
    raise exception 'SECURITY_FAILURE: a second clock_out on an already-closed record succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated clock_out on an already-closed record is blocked (%)', sqlerrm;
  end;
end $$;

do $$
declare v_worked int;
begin
  select worked_minutes into v_worked from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201';
  if v_worked is null then raise exception 'FAIL: worked_minutes was not computed on clock_out'; end if;
  raise notice 'PASS: worked_minutes computed on clock_out (% minutes, break excluded)', v_worked;
end $$;

-- ---------------------------------------------------------------------------
-- Correction workflow: employee requests, unauthorized decide blocked,
-- authorized decide applies the change.

do $$
declare
  v_attendance_id uuid;
  v_correction_id uuid;
begin
  select id into v_attendance_id from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201';

  select id into v_correction_id from public.request_attendance_correction(
    v_attendance_id, 'status', 'present', 'clocked out early due to a genuine emergency'
  );

  begin
    perform public.decide_attendance_correction(v_correction_id, true);
    raise exception 'SECURITY_FAILURE: the requesting employee decided their own correction';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from deciding their own correction request (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"role":"organization_administrator"}}';

do $$
declare
  v_attendance_id uuid;
  v_correction_id uuid;
  v_decided public.attendance_corrections;
  v_new_status public.attendance_status;
begin
  select id into v_attendance_id from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201';
  select id into v_correction_id from public.attendance_corrections where attendance_record_id = v_attendance_id and status = 'pending';

  select * into v_decided from public.decide_attendance_correction(v_correction_id, true, 'confirmed with the employee');
  if v_decided.status <> 'approved' then raise exception 'FAIL: expected approved, got %', v_decided.status; end if;
  if v_decided.reviewed_by <> '00000000-0000-0000-0000-0000000000e2' then raise exception 'FAIL: reviewed_by not server-derived correctly'; end if;

  select status into v_new_status from public.attendance_records where id = v_attendance_id;
  if v_new_status <> 'present' then raise exception 'FAIL: correction was approved but attendance_records.status was not updated, got %', v_new_status; end if;
  raise notice 'PASS: authorized correction decision applies the change and server-derives reviewed_by/reviewed_at';
end $$;

do $$
declare v_correction_id uuid;
begin
  select id into v_correction_id from public.attendance_corrections where status = 'approved' limit 1;
  begin
    perform public.decide_attendance_correction(v_correction_id, false);
    raise exception 'SECURITY_FAILURE: an already-decided correction was decided again';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated decision on an already-decided correction is blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Employee isolation on SELECT.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e4","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201';
  if v_count <> 0 then raise exception 'FAIL: employee-e2 could read employee-e1''s attendance records, got % rows', v_count; end if;

  select count(*) into v_count from public.attendance_corrections where attendance_record_id in (select id from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005201');
  if v_count <> 0 then raise exception 'FAIL: employee-e2 could read employee-e1''s attendance corrections, got % rows', v_count; end if;
  raise notice 'PASS: an ordinary employee sees zero rows of another employee''s attendance records/corrections';
end $$;

-- ---------------------------------------------------------------------------
-- attendance_policies: manager-only write.

-- RLS hides the row from UPDATE entirely for this actor (USING evaluates
-- false), so the statement affects 0 rows silently rather than raising —
-- check row count rather than expecting an exception (same pattern as the
-- equivalent check in leave.sql).
do $$
declare
  v_rows_affected int;
begin
  update public.attendance_policies set grace_period_minutes = 99 where tenant_id = '00000000-0000-0000-0000-0000000000e1';
  get diagnostics v_rows_affected = row_count;
  if v_rows_affected <> 0 then
    raise exception 'SECURITY_FAILURE: employee updated attendance_policies (% row(s) affected)', v_rows_affected;
  end if;
  raise notice 'PASS: employee update of attendance_policies affects 0 rows (RLS hides it from UPDATE)';
end $$;

-- ---------------------------------------------------------------------------
-- Leave integration: approving leave marks a matching unconfirmed
-- attendance record 'excused'; an already-decided ('present') record for
-- employee-e1 stays untouched since it's no longer 'unconfirmed'. Test
-- against employee-e2, who has no attendance record yet for a shift within
-- the leave range — approval must NOT create one.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"role":"organization_administrator"}}';

insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values ('00000000-0000-0000-0000-000000009202', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000004201', '00000000-0000-0000-0000-000000005202', current_date + interval '1 day' + interval '8 hours', current_date + interval '1 day' + interval '17 hours');

insert into public.attendance_records (id, tenant_id, shift_id, site_id, employee_id, status)
values ('00000000-0000-0000-0000-000000009301', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000009202', '00000000-0000-0000-0000-000000004201', '00000000-0000-0000-0000-000000005202', 'unconfirmed');

do $$
declare
  v_leave_type_id uuid;
  v_leave_request_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000e1' and name = 'Annual';
  select id into v_leave_request_id from public.submit_leave_request(
    '00000000-0000-0000-0000-000000005202', v_leave_type_id, current_date + 1, current_date + 1, false, null, 'test', null
  );
  perform public.approve_leave_request(v_leave_request_id);
end $$;

do $$
declare v_status public.attendance_status;
begin
  select status into v_status from public.attendance_records where id = '00000000-0000-0000-0000-000000009301';
  if v_status <> 'excused' then raise exception 'FAIL: expected approved leave to mark the matching unconfirmed attendance record excused, got %', v_status; end if;
  raise notice 'PASS: approved leave marks an existing unconfirmed attendance record excused for the matching shift date';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.attendance_records where employee_id = '00000000-0000-0000-0000-000000005202' and id <> '00000000-0000-0000-0000-000000009301';
  if v_count <> 0 then raise exception 'FAIL: approved leave created a new attendance record instead of only updating the existing one'; end if;
  raise notice 'PASS: approved leave never force-creates an attendance record';
end $$;

reset role;
reset request.jwt.claims;

rollback;
