-- Regression suite for FND-PAR-003 / FND-PAR-004
-- (20260829120000_parent_portal_timetable_and_documents.sql): guardian
-- visibility into timetable_entries (reference data, tenant + role scoped)
-- and learner_documents + the learner-documents storage bucket (personal
-- data, is_learner_guardian(learner_id) scoped).
--
-- Uses School A/B, learner A1 (11110000...0001, School A, enrolled in
-- class cccc1111...0001, guardian 55555555 as mother — 05_learner_
-- fixtures.sql), learner A2 (11110000...0002, School A, NOT linked to
-- guardian 55555555), academic year aaaa1111...0001, subject
-- facade00...0001, teacher 11111111 (all School A, various earlier
-- fixture files), and principal 77777777 (School A) for setup writes.

-- ---------------------------------------------------------------------------
-- SETUP: principal creates one timetable entry for Learner A1's class, and
-- one document each for Learner A1 and Learner A2.
do $$
declare v_ok boolean := true;
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('7e000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
              'tuesday', '08:00', '09:00', 'Room 4');

    insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name)
      values ('dc000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
              'report_card', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/report.pdf', 'report.pdf');
    insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name)
      values ('dc000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002',
              'report_card', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000002/report.pdf', 'report.pdf');

    insert into storage.objects (bucket_id, name)
      values ('learner-documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/report.pdf');
    insert into storage.objects (bucket_id, name)
      values ('learner-documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000002/report.pdf');
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('setup: principal creates a timetable entry and two documents (A1, A2)', v_ok, coalesce(v_error, 'created'));
end $$;

-- ---------------------------------------------------------------------------
-- 1. Guardian 55555555 (Learner A1's mother) can see the timetable entry
-- for A1's class — reference data, tenant + role scoped, not per-learner.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_entries where id = '7e000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see the timetable entry for their child''s class', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Cross-tenant: School B's owner cannot see School A's timetable entry.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_entries where id = '7e000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant: School B''s owner cannot see School A''s timetable entry', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Guardian 55555555 sees Learner A1's document (their own linked child).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id = 'dc000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see their own linked learner''s document row', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Guardian 55555555 does NOT see Learner A2's document — not their
-- child, even though same school (precise is_learner_guardian() scoping,
-- not the broader reference-data treatment given to timetable_entries).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id = 'dc000000-0000-0000-0000-000000000002';
  execute 'reset role';
  call test_util.record('guardian cannot see an unrelated learner''s document row, even same-school', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. The same split holds for the actual storage object, not just the
-- metadata row: guardian can read A1's file, not A2's.
do $$
declare v_count_a1 int;
declare v_count_a2 int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count_a1 from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/report.pdf';
  select count(*) into v_count_a2 from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000002/report.pdf';
  execute 'reset role';
  call test_util.record('guardian can read their own child''s document file, not an unrelated child''s',
    v_count_a1 = 1 and v_count_a2 = 0, 'A1 visible: ' || v_count_a1 || ', A2 visible: ' || v_count_a2);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Staff visibility is unaffected by the new guardian policies.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id in ('dc000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000002');
  execute 'reset role';
  call test_util.record('staff (principal) still sees both documents unaffected by the guardian policies', v_count = 2, 'rows visible: ' || v_count);
end $$;
