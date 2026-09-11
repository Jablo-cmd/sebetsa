-- Regression suite for FND-COM-003 (20260829140000_announcements.sql):
-- the announcements table, its audience-scoped RLS, and the
-- announcements_notify_recipients() fan-out trigger.
--
-- Uses School A (school_owner 22222222, teacher 11111111, guardian
-- 55555555 — 02_fixtures.sql/05_learner_fixtures.sql) and School B
-- (school_owner 66666666 — 02_fixtures.sql).
--
-- Exact-count assertions are scoped to a specific recipient AND
-- `type = 'announcement'` throughout — never an unscoped
-- `count(*) from notifications for <shared fixture>` — because these
-- announcements fan out to every active School A profile, which by this
-- point in the suite includes many profiles other test files created;
-- asserting "did guardian 55555555 get exactly one announcement
-- notification with this title" is robust to that, an unscoped total
-- count would not be (the same lesson attendance_alerts.test.sql already
-- had to learn about a different table).

-- ---------------------------------------------------------------------------
-- 1. A teacher (no school.manage) cannot post an announcement.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.announcements (school_id, title, body, audience) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rogue announcement', 'Should not be allowed.', 'everyone');
    call test_util.record('a teacher cannot post an announcement', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot post an announcement', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. school_owner (can_manage_school) posts an 'everyone' announcement —
-- fans out to both a guardian (55555555) and a teacher (11111111), but NOT
-- back to the poster themselves.
do $$
declare v_id uuid;
declare v_count_guardian int;
declare v_count_teacher int;
declare v_count_poster int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.announcements (school_id, title, body, audience) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sports day next Friday', 'All welcome.', 'everyone')
    returning id into v_id;
  execute 'reset role';

  select count(*) into v_count_guardian from public.notifications where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'announcement' and related_entity_id = v_id;
  select count(*) into v_count_teacher from public.notifications where recipient_profile_id = '11111111-1111-1111-1111-111111111111' and type = 'announcement' and related_entity_id = v_id;
  select count(*) into v_count_poster from public.notifications where recipient_profile_id = '22222222-2222-2222-2222-222222222222' and type = 'announcement' and related_entity_id = v_id;

  call test_util.record('an everyone announcement notifies a guardian', v_count_guardian = 1, 'rows: ' || v_count_guardian);
  call test_util.record('an everyone announcement notifies a teacher', v_count_teacher = 1, 'rows: ' || v_count_teacher);
  call test_util.record('an everyone announcement does not notify its own poster', v_count_poster = 0, 'rows: ' || v_count_poster);
end $$;

-- ---------------------------------------------------------------------------
-- 3. The guardian's notification routes to the Parent Portal path; the
-- teacher's routes to the staff path — same recipient-role-based split
-- NotificationBell's own `to` prop already needs.
do $$
declare v_guardian_link text;
declare v_teacher_link text;
begin
  select link_path into v_guardian_link from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'announcement'
    order by created_at desc limit 1;
  select link_path into v_teacher_link from public.notifications
    where recipient_profile_id = '11111111-1111-1111-1111-111111111111' and type = 'announcement'
    order by created_at desc limit 1;

  call test_util.record('a guardian recipient''s link_path points at the Parent Portal', v_guardian_link = '/parent/announcements', 'link_path=' || coalesce(v_guardian_link, '(null)'));
  call test_util.record('a staff recipient''s link_path points at the staff route', v_teacher_link = '/announcements', 'link_path=' || coalesce(v_teacher_link, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. A staff-only announcement is visible to the teacher but NOT the
-- guardian; a guardians-only announcement is the reverse.
do $$
declare v_staff_id uuid;
declare v_guardian_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.announcements (school_id, title, body, audience) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Staff meeting Monday', 'Staffroom, 07:30.', 'all_staff')
    returning id into v_staff_id;
  insert into public.announcements (school_id, title, body, audience) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Uniform shop hours', 'Open Tuesdays 08:00-10:00.', 'all_guardians')
    returning id into v_guardian_id;

  declare v_count int;
  begin
    -- Still under the same school_owner session as the INSERT above — a
    -- manager can see their own all_guardians-only post even though
    -- school_owner itself isn't in the guardian audience. This is also
    -- what makes `INSERT ... RETURNING` above succeed at all: RETURNING
    -- re-checks the SELECT policy on the row it returns.
    select count(*) into v_count from public.announcements where id = v_guardian_id;
    call test_util.record('the posting manager can see their own all_guardians-only announcement', v_count = 1, 'rows visible: ' || v_count);
  end;
  execute 'reset role';

  declare v_count int;
  begin
    perform set_config('request.jwt.claims',
      test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
    execute 'set local role authenticated';
    select count(*) into v_count from public.announcements where id = v_staff_id;
    execute 'reset role';
    call test_util.record('a guardian cannot see an all_staff announcement', v_count = 0, 'rows visible: ' || v_count);
  end;

  declare v_count int;
  begin
    perform set_config('request.jwt.claims',
      test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
    execute 'set local role authenticated';
    select count(*) into v_count from public.announcements where id = v_guardian_id;
    execute 'reset role';
    call test_util.record('a guardian can see an all_guardians announcement', v_count = 1, 'rows visible: ' || v_count);
  end;

  declare v_count int;
  begin
    perform set_config('request.jwt.claims',
      test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
    execute 'set local role authenticated';
    select count(*) into v_count from public.announcements where id = v_guardian_id;
    execute 'reset role';
    call test_util.record('a teacher cannot see an all_guardians announcement', v_count = 0, 'rows visible: ' || v_count);
  end;

  declare v_count int;
  begin
    perform set_config('request.jwt.claims',
      test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
    execute 'set local role authenticated';
    select count(*) into v_count from public.announcements where id = v_staff_id;
    execute 'reset role';
    call test_util.record('a teacher can see an all_staff announcement', v_count = 1, 'rows visible: ' || v_count);
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's owner cannot see or post School A's
-- announcements.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.announcements where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('School B''s owner cannot see School A''s announcements', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.announcements (school_id, title, body, audience) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Cross-tenant announcement', 'Should not be allowed.', 'everyone');
    call test_util.record('School B''s owner cannot post into School A', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot post into School A', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. school_owner can archive their own announcement; hard delete is
-- impossible even for them.
do $$
declare v_id uuid;
declare v_active boolean;
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.announcements (school_id, title, body, audience) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Temporary notice', 'Withdrawn shortly.', 'everyone')
    returning id into v_id;

  update public.announcements set active = false where id = v_id;
  select active into v_active from public.announcements where id = v_id;

  delete from public.announcements where id = v_id;
  get diagnostics v_deleted = row_count;
  execute 'reset role';

  call test_util.record('school_owner can archive their own announcement', v_active = false, 'active=' || v_active);
  call test_util.record('hard delete of an announcement is impossible even for school_owner', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
