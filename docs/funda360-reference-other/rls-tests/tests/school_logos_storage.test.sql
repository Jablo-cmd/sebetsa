-- Regression suite for the school-logos storage bucket's RLS policies
-- (20260821100000_storage_buckets_and_documents.sql). Exercises
-- storage.objects directly, the same way the real Storage API would
-- evaluate access for an upload/download/list call — see
-- 00b_storage_stub.sql for why this is possible against the bare-Postgres
-- harness. Uses School A/B and users from 02_fixtures.sql + principal A1
-- (77777777) from 04_employee_fixtures.sql.

-- ---------------------------------------------------------------------------
-- 1. Authorized manager (school_owner) can upload School A's logo.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name) values ('school-logos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo');
  select count(*) into v_count from storage.objects where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  execute 'reset role';
  call test_util.record('school_owner can upload their own school''s logo', v_count = 1, 'rows created: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Any School A member (not just manager-tier) can read the logo back —
-- branding isn't sensitive to a school's own staff.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from storage.objects where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  execute 'reset role';
  call test_util.record('any authenticated member of the school can read its logo', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Cross-tenant read: School B's teacher cannot see School A's logo.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from storage.objects where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  execute 'reset role';
  call test_util.record('cross-tenant: School B cannot read School A''s logo object', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (view-tier, not manage-tier) cannot upload/replace the
-- school logo — only can_manage_school() may write.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into storage.objects (bucket_id, name) values ('school-logos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo-attempt-2');
    call test_util.record('a teacher cannot upload the school logo', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot upload the school logo', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant write: School B's owner cannot upload into School A's
-- logo path.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into storage.objects (bucket_id, name) values ('school-logos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo-hijack');
    call test_util.record('School B''s owner cannot upload into School A''s logo path', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot upload into School A''s logo path', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Principal (also can_manage_school) can replace/overwrite the logo —
-- proves the fixed-path + upsert design: this UPDATEs the same row rather
-- than needing a second object, so replacement can never orphan the
-- previous file.
do $$
declare v_updated int; v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update storage.objects set metadata = '{"mimetype":"image/png"}'::jsonb
    where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  get diagnostics v_updated = row_count;
  select count(*) into v_count from storage.objects where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  execute 'reset role';
  call test_util.record('principal can replace the logo in place, never creating a second object', v_updated = 1 and v_count = 1, 'updated=' || v_updated || ' total objects at path=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. No DELETE policy exists on this bucket — a manager cannot remove the
-- object row directly (the app never offers a "remove logo" action either;
-- this is a deliberate, matching absence, not a gap).
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id = 'school-logos' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/logo';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('deleting the logo object is impossible even for an authorized manager (no DELETE policy)', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
