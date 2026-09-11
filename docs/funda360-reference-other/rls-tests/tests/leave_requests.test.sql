-- Regression suite for FND-HR-004 (20260829230000_leave_management.sql):
-- leave_requests RLS (self-INSERT/SELECT, manager-only UPDATE), the
-- force-pending-on-insert trigger, and the server-derived reviewed_by/
-- reviewed_at sync on approval/rejection.
--
-- Uses 04_employee_fixtures.sql: hr_manager 88888888 (School A, can
-- manage), employee "Manager A" eeee1111...0001 (no login — the
-- manager-logs-it-on-someone's-behalf case), employee "Teacher A1"
-- eeee1111...0002 (profile_id = teacher 11111111 — the self-service
-- fixture), employee "Teacher B1" eeee2222...0001 (School B).

-- ---------------------------------------------------------------------------
-- 1. An employee (teacher 11111111, linked to "Teacher A1") can request
-- their own leave — and it is forced to 'pending' regardless of what was
-- sent, closing the self-approve-on-insert loophole.
do $$
declare v_status public.leave_request_status;
declare v_reviewed_by uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.leave_requests (id, school_id, employee_id, leave_type, start_date, end_date, reason, status, reviewed_by) values
    ('7f500000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000002',
     'annual', '2026-09-14', '2026-09-16', 'Family trip', 'approved', '11111111-1111-1111-1111-111111111111');
  execute 'reset role';

  select status, reviewed_by into v_status, v_reviewed_by from public.leave_requests where id = '7f500000-0000-0000-0000-000000000001';
  call test_util.record('a self-submitted leave request is forced to pending regardless of what was sent', v_status = 'pending', 'status=' || v_status);
  call test_util.record('reviewed_by is cleared on insert even if the client tried to set it', v_reviewed_by is null, 'reviewed_by=' || coalesce(v_reviewed_by::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. That employee can see their own request.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.leave_requests where id = '7f500000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('an employee can see their own leave request', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. That employee CANNOT approve/edit their own request (no self-service
-- update in this version) — an UPDATE with no policy match under FORCE
-- ROW LEVEL SECURITY is a silent 0-row no-op, not a raised exception, so
-- this is checked via the row's unchanged state rather than expecting an
-- error.
do $$
declare v_status public.leave_request_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.leave_requests set status = 'approved' where id = '7f500000-0000-0000-0000-000000000001';
  execute 'reset role';

  select status into v_status from public.leave_requests where id = '7f500000-0000-0000-0000-000000000001';
  call test_util.record('an employee cannot approve their own leave request', v_status = 'pending', 'status=' || v_status);
end $$;

-- ---------------------------------------------------------------------------
-- 4. hr_manager approves it — reviewed_by/reviewed_at are server-derived,
-- never trusted from the client.
do $$
declare v_status public.leave_request_status;
declare v_reviewed_by uuid;
declare v_reviewed_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.leave_requests set status = 'approved', review_notes = 'Enjoy the trip' where id = '7f500000-0000-0000-0000-000000000001';
  execute 'reset role';

  select status, reviewed_by, reviewed_at into v_status, v_reviewed_by, v_reviewed_at from public.leave_requests where id = '7f500000-0000-0000-0000-000000000001';
  call test_util.record('hr_manager can approve a leave request', v_status = 'approved', 'status=' || v_status);
  call test_util.record('reviewed_by is server-derived from the approving manager', v_reviewed_by = '88888888-8888-8888-8888-888888888888', 'reviewed_by=' || coalesce(v_reviewed_by::text, '(null)'));
  call test_util.record('reviewed_at is populated on approval', v_reviewed_at is not null, 'reviewed_at=' || coalesce(v_reviewed_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. hr_manager can also log a leave request on behalf of an employee with
-- no login (Manager A), and reject it.
do $$
declare v_status public.leave_request_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.leave_requests (id, school_id, employee_id, leave_type, start_date, end_date, reason) values
    ('7f500000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000001',
     'sick', '2026-09-20', '2026-09-20', 'Called in sick');
  update public.leave_requests set status = 'rejected', review_notes = 'Insufficient notice' where id = '7f500000-0000-0000-0000-000000000002';
  execute 'reset role';

  select status into v_status from public.leave_requests where id = '7f500000-0000-0000-0000-000000000002';
  call test_util.record('hr_manager can log and reject a leave request on an employee''s behalf', v_status = 'rejected', 'status=' || v_status);
end $$;

-- ---------------------------------------------------------------------------
-- 6. A different, unrelated employee cannot see someone else's leave
-- request.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('99999999-9999-9999-9999-999999999999', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.leave_requests where employee_id = 'eeee1111-0000-0000-0000-000000000002';
  execute 'reset role';
  call test_util.record('an unrelated employee cannot see someone else''s leave request', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Tenant isolation: School B cannot see School A's leave requests.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.leave_requests where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s leave requests', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. The tenant-consistency trigger rejects an employee_id from a
-- different school.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.leave_requests (school_id, employee_id, leave_type, start_date, end_date, reason) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee2222-0000-0000-0000-000000000001', 'annual', '2026-09-01', '2026-09-02', 'Mismatched school');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('an employee_id from a different school is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 9. An end_date before start_date is rejected by the check constraint.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.leave_requests (school_id, employee_id, leave_type, start_date, end_date, reason) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eeee1111-0000-0000-0000-000000000001', 'annual', '2026-09-10', '2026-09-05', 'Invalid range');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('an end_date before start_date is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;
