-- Regression suite for FND-TT-003 (20260829200000_timetable_publish_status.sql):
-- timetable_entries.status (draft/published) and the RLS narrowing that
-- makes a draft invisible to non-managers, including guardians.
--
-- Uses School A fixtures already established by timetable.test.sql /
-- parent_portal_timetable_and_documents.test.sql: school_owner 22222222,
-- teacher 11111111 (view only, no manage), guardian 55555555 (linked to
-- learner A1, enrolled in class cccc1111...0001), academic year
-- aaaa1111...0001, subject facade00...0001, class cccc1111...0001. Uses a
-- distinct day/time (wednesday 10:00-11:00) from every other timetable
-- fixture row already inserted by those two files, to avoid the
-- teacher/class/room conflict trigger.

-- ---------------------------------------------------------------------------
-- 1. A manager (school_owner) creates a DRAFT entry — new entries default
-- to 'published', so this must be explicit.
do $$
declare v_status public.timetable_entry_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, status) values
    ('7f100000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
     'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
     'wednesday', '10:00', '11:00', 'draft');

  execute 'reset role';

  select status into v_status from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  call test_util.record('a new entry defaults to published unless draft is explicit', v_status = 'draft', 'status=' || v_status);
end $$;

-- ---------------------------------------------------------------------------
-- 2. The manager who created it can still see their own draft.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a manager can see their own draft entry', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher (timetable.view, no timetable.manage) cannot see the draft.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a viewer without manage cannot see a draft entry', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A guardian linked to a learner in that class cannot see the draft
-- entry either.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a guardian cannot see a draft timetable entry', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Publishing it (the manager flips status to 'published', matching
-- timetableService.publishDraftEntries's own bulk UPDATE) makes it visible
-- to both the teacher and the guardian.
do $$
declare v_teacher_count int;
declare v_guardian_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.timetable_entries set status = 'published' where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_teacher_count from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_guardian_count from public.timetable_entries where id = '7f100000-0000-0000-0000-000000000001';
  execute 'reset role';

  call test_util.record('publishing a draft makes it visible to a viewer-only teacher', v_teacher_count = 1, 'count=' || v_teacher_count);
  call test_util.record('publishing a draft makes it visible to a linked guardian', v_guardian_count = 1, 'count=' || v_guardian_count);
end $$;
