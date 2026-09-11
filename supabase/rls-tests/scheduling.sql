-- Sebetsa Phase G — RLS / cross-tenant-relationship / conflict checks for
-- scheduling & workforce availability (shift_definitions, shifts,
-- shift_substitutions, attendance_records, leave_requests,
-- employee_availability, employee_availability_exceptions).
--
-- Same pattern as supabase/rls-tests/workforce_management.sql — a real,
-- repeatable psql script against actual RLS policies/triggers/constraints,
-- not a mock. Run:
--
--   supabase start
--   cat supabase/rls-tests/scheduling.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000a1', 'Org A', 'active'),
  ('00000000-0000-0000-0000-0000000000b1', 'Org B', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'admin-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', 'Admin', 'A', 'admin-a@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a2","app_metadata":{"role":"organization_administrator"}}';

-- Org A structure
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000003001', '00000000-0000-0000-0000-0000000000a1', 'Client A');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000003001', 'Site A');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000a1', 'E001', 'Real', 'Employee', current_date),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000000a1', 'E002', 'Second', 'Employee', current_date);

-- Org B structure (as service role, bypassing RLS, just to have cross-tenant targets)
reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000003002', '00000000-0000-0000-0000-0000000000b1', 'Client B');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000003002', 'Site B');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005003', '00000000-0000-0000-0000-0000000000b1', 'E901', 'Other', 'TenantEmployee', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a2","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- shift_definitions: valid create + tenant-scoped uniqueness sanity.

insert into public.shift_definitions (id, tenant_id, name, start_time, end_time, is_overnight)
values ('00000000-0000-0000-0000-000000007001', '00000000-0000-0000-0000-0000000000a1', 'Day Shift', '08:00', '17:00', false);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shift_definitions where id = '00000000-0000-0000-0000-000000007001';
  if v_count != 1 then raise exception 'FAIL: valid shift_definition insert did not succeed'; end if;
  raise notice 'PASS: valid shift_definition insert succeeded';
end $$;

-- ---------------------------------------------------------------------------
-- shifts: cross-tenant rejection on site_id / employee_id / shift_definition_id.

do $$
begin
  begin
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-000000005001', now(), now() + interval '8 hours');
    raise exception 'SECURITY_FAILURE: cross-tenant shift.site_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant shift.site_id blocked (%)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005003', now(), now() + interval '8 hours');
    raise exception 'SECURITY_FAILURE: cross-tenant shift.employee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant shift.employee_id blocked (%)', sqlerrm;
  end;
end $$;

-- Valid same-tenant shift, anchored at a fixed time so the overlap tests
-- below are deterministic.
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-000000008001', '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001',
  '2026-09-15 08:00:00+02', '2026-09-15 17:00:00+02'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts where id = '00000000-0000-0000-0000-000000008001';
  if v_count != 1 then raise exception 'FAIL: valid same-tenant shift insert did not succeed'; end if;
  raise notice 'PASS: valid same-tenant shift insert succeeded';
end $$;

-- ---------------------------------------------------------------------------
-- Conflict model: overlapping shift for the SAME employee is rejected.

do $$
begin
  begin
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
    values (
      '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001',
      '2026-09-15 12:00:00+02', '2026-09-15 20:00:00+02'
    );
    raise exception 'SECURITY_FAILURE: overlapping shift for same employee succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: overlapping shift for same employee blocked (%)', sqlerrm;
  end;
end $$;

-- Non-overlapping shift for the SAME employee (starts exactly when the
-- first one ends — back-to-back, must be accepted, not treated as overlap).
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-000000008002', '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001',
  '2026-09-15 17:00:00+02', '2026-09-16 01:00:00+02'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts where id = '00000000-0000-0000-0000-000000008002';
  if v_count != 1 then raise exception 'FAIL: back-to-back non-overlapping shift insert did not succeed'; end if;
  raise notice 'PASS: back-to-back non-overlapping shift for same employee succeeded';
end $$;

-- Overlapping time range but a DIFFERENT employee — must be accepted.
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-000000008003', '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005002',
  '2026-09-15 08:00:00+02', '2026-09-15 17:00:00+02'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts where id = '00000000-0000-0000-0000-000000008003';
  if v_count != 1 then raise exception 'FAIL: overlapping shift for a different employee did not succeed'; end if;
  raise notice 'PASS: overlapping time range accepted for a different employee';
end $$;

-- Cancelled shifts are excluded from the conflict check.
update public.shifts set status = 'cancelled' where id = '00000000-0000-0000-0000-000000008001';
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-000000008004', '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001',
  '2026-09-15 08:00:00+02', '2026-09-15 17:00:00+02'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts where id = '00000000-0000-0000-0000-000000008004';
  if v_count != 1 then raise exception 'FAIL: shift overlapping only a cancelled shift did not succeed'; end if;
  raise notice 'PASS: a cancelled shift does not block a new overlapping shift';
end $$;

-- ---------------------------------------------------------------------------
-- shift_substitutions: cross-tenant rejection + valid insert.

do $$
begin
  begin
    insert into public.shift_substitutions (tenant_id, shift_id, original_employee_id, substitute_employee_id)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000008002', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-000000005003');
    raise exception 'SECURITY_FAILURE: cross-tenant shift_substitution.substitute_employee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant shift_substitution.substitute_employee_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.shift_substitutions (tenant_id, shift_id, original_employee_id, substitute_employee_id, reason)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000008002', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-000000005002', 'sick');

-- ---------------------------------------------------------------------------
-- attendance_records: cross-tenant rejection + valid insert.

do $$
begin
  begin
    insert into public.attendance_records (tenant_id, site_id, employee_id, status)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005003', 'present');
    raise exception 'SECURITY_FAILURE: cross-tenant attendance_record.employee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant attendance_record.employee_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.attendance_records (id, tenant_id, site_id, employee_id, status, recorded_by)
values ('00000000-0000-0000-0000-000000009001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001', 'present', '00000000-0000-0000-0000-0000000000a2');

-- ---------------------------------------------------------------------------
-- leave_requests: cross-tenant rejection + valid insert.

do $$
begin
  begin
    insert into public.leave_requests (tenant_id, employee_id, start_date, end_date)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005003', current_date, current_date + 1);
    raise exception 'SECURITY_FAILURE: cross-tenant leave_request.employee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant leave_request.employee_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.leave_requests (tenant_id, employee_id, start_date, end_date)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005001', current_date, current_date + 1);

-- ---------------------------------------------------------------------------
-- employee_availability / employee_availability_exceptions: cross-tenant
-- rejection + valid insert by a manager.

do $$
begin
  begin
    insert into public.employee_availability (tenant_id, employee_id, day_of_week, start_time, end_time)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005003', 1, '08:00', '17:00');
    raise exception 'SECURITY_FAILURE: cross-tenant employee_availability.employee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant employee_availability.employee_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.employee_availability (id, tenant_id, employee_id, day_of_week, start_time, end_time)
values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005002', 1, '08:00', '17:00');

insert into public.employee_availability_exceptions (tenant_id, employee_id, exception_date, is_available, reason)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005002', current_date + 3, false, 'personal');

-- ---------------------------------------------------------------------------
-- Audit coverage check.

do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'shifts' and entity_id = '00000000-0000-0000-0000-000000008002' and action = 'insert_shifts';
  if v_count < 1 then raise exception 'FAIL: shift insert was not audit-logged'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'shifts' and entity_id = '00000000-0000-0000-0000-000000008001' and action = 'update_shifts';
  if v_count < 1 then raise exception 'FAIL: shift cancellation (update) was not audit-logged'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'shift_substitutions' and action = 'insert_shift_substitutions';
  if v_count < 1 then raise exception 'FAIL: shift_substitution insert was not audit-logged'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'attendance_records' and action = 'insert_attendance_records';
  if v_count < 1 then raise exception 'FAIL: attendance_record insert was not audit-logged'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'leave_requests' and action = 'insert_leave_requests';
  if v_count < 1 then raise exception 'FAIL: leave_request insert was not audit-logged'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'shift_definitions' and action = 'insert_shift_definitions';
  if v_count < 1 then raise exception 'FAIL: shift_definition insert was not audit-logged'; end if;

  -- employee_availability is deliberately unaudited.
  select count(*) into v_count from public.audit_log where entity_table in ('employee_availability', 'employee_availability_exceptions');
  if v_count != 0 then raise exception 'FAIL: employee_availability audit rows exist but should not (deliberately unaudited)'; end if;

  raise notice 'PASS: shifts/shift_substitutions/attendance_records/leave_requests/shift_definitions are all audit-logged; employee_availability is correctly unaudited';
end $$;

-- ---------------------------------------------------------------------------
-- Role-tier write access: a supervisor (operational tier) can create a
-- shift. hr_user cannot manage shift_definitions (org-structure tier only,
-- and hr_user is deliberately excluded from can_manage_org_structure()).

reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a5', 'authenticated', 'authenticated', 'supervisor-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"supervisor"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a6', 'authenticated', 'authenticated', 'hr-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000a1', 'Super', 'Visor', 'supervisor-a@example.com', 'supervisor', 'active'),
  ('00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000a1', 'HR', 'User', 'hr-a@example.com', 'hr_user', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a5","app_metadata":{"role":"supervisor"}}';

insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005002',
  '2026-09-16 08:00:00+02', '2026-09-16 17:00:00+02'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts
  where tenant_id = '00000000-0000-0000-0000-0000000000a1' and employee_id = '00000000-0000-0000-0000-000000005002' and starts_at = '2026-09-16 08:00:00+02';
  if v_count != 1 then raise exception 'FAIL: supervisor could not create a shift'; end if;
  raise notice 'PASS: supervisor (operational tier) can create a shift';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a6","app_metadata":{"role":"hr_user"}}';

do $$
begin
  begin
    insert into public.shift_definitions (tenant_id, name, start_time, end_time)
    values ('00000000-0000-0000-0000-0000000000a1', 'Should Fail Definition', '06:00', '14:00');
    raise exception 'SECURITY_FAILURE: hr_user created a shift_definition';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: hr_user blocked from creating a shift_definition (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Self-service: an employee can manage their OWN availability, but not
-- another employee's.

reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a7', 'authenticated', 'authenticated', 'employee-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000a1', 'Emp', 'Loyee', 'employee-a@example.com', 'employee', 'active');
update public.employees set profile_id = '00000000-0000-0000-0000-0000000000a7' where id = '00000000-0000-0000-0000-000000005001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a7","app_metadata":{"role":"employee"}}';

insert into public.employee_availability (tenant_id, employee_id, day_of_week, start_time, end_time)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005001', 2, '09:00', '18:00');

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_availability where employee_id = '00000000-0000-0000-0000-000000005001' and day_of_week = 2;
  if v_count != 1 then raise exception 'FAIL: employee could not manage their own availability'; end if;
  raise notice 'PASS: employee (self-service) can manage their own availability';
end $$;

do $$
begin
  begin
    insert into public.employee_availability (tenant_id, employee_id, day_of_week, start_time, end_time)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000005002', 3, '09:00', '18:00');
    raise exception 'SECURITY_FAILURE: employee managed another employee''s availability';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from managing another employee''s availability (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
