-- Regression suite for FND-ATT-003 (20260829220000_staff_attendance.sql):
-- staff_attendance_records RLS (can_view_employees()/can_manage_employees()
-- plus the employees.profile_id self-access clause), tenant-consistency,
-- and the one-row-per-employee-per-day uniqueness invariant.
--
-- Uses 04_employee_fixtures.sql: hr_manager 88888888 (School A, can
-- manage), employee "Manager A" eeee1111...0001 (no login), employee
-- "Teacher A1" eeee1111...0002 (profile_id = teacher 11111111 — the
-- self-access fixture), employee "Teacher B1" eeee2222...0001 (School B).

-- ---------------------------------------------------------------------------
-- 1. hr_manager records attendance for an employee with no login — succeeds.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.staff_attendance_records (id, school_id, employee_id, attendance_date, status) values
    ('7f400000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000001', '2026-08-31', 'present');
  execute 'reset role';

  select count(*) into v_count from public.staff_attendance_records where id = '7f400000-0000-0000-0000-000000000001';
  call test_util.record('hr_manager can record staff attendance', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. hr_manager also records an attendance row for the self-access
-- employee (Teacher A1, linked to profile 11111111).
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.staff_attendance_records (id, school_id, employee_id, attendance_date, status) values
    ('7f400000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000002', '2026-08-31', 'late');
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher with no employee.view (11111111, linked to the "Teacher A1"
-- employee row) can see their OWN attendance record via self-access, but
-- not the Manager's.
do $$
declare v_own_count int;
declare v_other_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_own_count from public.staff_attendance_records where id = '7f400000-0000-0000-0000-000000000002';
  select count(*) into v_other_count from public.staff_attendance_records where id = '7f400000-0000-0000-0000-000000000001';
  execute 'reset role';

  call test_util.record('a teacher can see their own staff attendance record via self-access', v_own_count = 1, 'count=' || v_own_count);
  call test_util.record('a teacher cannot see another employee''s attendance record', v_other_count = 0, 'count=' || v_other_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. That same teacher cannot INSERT a staff attendance record at all
-- (view-only self-access does not imply manage).
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.staff_attendance_records (school_id, employee_id, attendance_date, status) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000002', '2026-09-01', 'present');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a teacher cannot record staff attendance, even their own', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. Tenant isolation: School B cannot see School A's staff attendance.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.staff_attendance_records where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s staff attendance', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. The tenant-consistency trigger rejects an employee_id from a
-- different school.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.staff_attendance_records (school_id, employee_id, attendance_date, status) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee2222-0000-0000-0000-000000000001', '2026-09-01', 'present');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('an employee_id from a different school is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 7. A duplicate (employee_id, attendance_date) is rejected — one record
-- per employee per day, same invariant as attendance_records.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.staff_attendance_records (school_id, employee_id, attendance_date, status) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000001', '2026-08-31', 'absent');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a duplicate employee/date attendance record is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;
