-- Regression suite for the Parent Portal Completion domain
-- (20260909090000_parent_portal_completion.sql): the guardian's
-- SECURITY DEFINER read of the admission application(s) they filed,
-- get_my_admission_applications(), matched by their own profile email.
--
-- Fixtures: profile 55555555 (parent.a1@schoola.test, School A),
-- 59595959 (father.a1@schoola.test), school_owner 22222222.

-- ---------------------------------------------------------------------------
-- 1. Staff file + submit an application under 55555555's email address.
do $$
declare v_app uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_admission_application(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'parent.a1@schoola.test', 'Parent', 'A1', 'New', 'Child')).id into v_app;
  perform public.submit_admission_application(v_app);

  -- A second, still-draft application under the same email must NOT surface.
  perform public.create_admission_application(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'parent.a1@schoola.test', 'Parent', 'A1', 'Draft', 'Child');
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. The matching guardian sees exactly their one submitted application.
do $$
declare v_count int; v_status text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.get_my_admission_applications();
  select status::text into v_status from public.get_my_admission_applications() limit 1;
  execute 'reset role';
  call test_util.record('a guardian sees their own submitted application via the RPC', v_count = 1, 'rows: ' || v_count);
  call test_util.record('the returned application is the submitted one, not the draft', v_status = 'submitted', 'status: ' || coalesce(v_status, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. A different guardian (different email) sees nothing.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('59595959-5959-5959-5959-595959595959', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.get_my_admission_applications();
  execute 'reset role';
  call test_util.record('a guardian with a different email sees no applications', v_count = 0, 'rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. The guardian still cannot SELECT admission_applications directly
--    (no guardian RLS policy — the RPC is the only path).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.admission_applications where lower(applicant_email) = 'parent.a1@schoola.test';
  execute 'reset role';
  call test_util.record('a guardian cannot read admission_applications directly', v_count = 0, 'rows visible: ' || v_count);
end $$;
