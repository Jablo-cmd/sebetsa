-- Regression suite for the learner-documents storage bucket's RLS policies
-- (20260821100000_storage_buckets_and_documents.sql). Mirrors
-- learner_documents.test.sql's role split exactly (can_view_learners /
-- can_manage_learners), since both the table row and the file it points
-- to are meant to be authorized identically. Uses learner
-- 11110000-0000-0000-0000-000000000001 (School A) and users from
-- 02_fixtures.sql + 04_employee_fixtures.sql.

-- ---------------------------------------------------------------------------
-- 1. Authorized manager (principal) can upload a document for a School A
-- learner.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name)
  values ('learner-documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf');
  select count(*) into v_count from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  execute 'reset role';
  call test_util.record('an authorized manager can upload a document for a learner in their school', v_count = 1, 'rows created: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. A different authorized manager (school_owner) can read it back.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  execute 'reset role';
  call test_util.record('an authorized manager can read a document uploaded by a different authorized manager', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher (no learner.view in this role model — see
-- learner_documents.test.sql) cannot read the file object either. File
-- access matches row access exactly.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  execute 'reset role';
  call test_util.record('a teacher cannot read a learner document file (unauthorized read)', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant: School B's owner cannot see School A's learner document
-- file at all.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  execute 'reset role';
  call test_util.record('cross-tenant access to a learner document file is denied', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant write: School B's owner cannot upload into School A's
-- folder even with the correct-looking path.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into storage.objects (bucket_id, name)
    values ('learner-documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/hijacked.pdf');
    call test_util.record('School B''s owner cannot upload into School A''s learner-documents folder', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot upload into School A''s learner-documents folder', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Unauthorized update: a teacher cannot modify the object's metadata
-- either (update requires can_manage_learners, same as insert). Unlike
-- INSERT's WITH CHECK, an UPDATE whose USING clause matches nothing simply
-- affects 0 rows rather than raising — asserted via row count, not an
-- exception.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update storage.objects set metadata = '{"tampered":true}'::jsonb
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('a teacher cannot update a learner document file''s metadata', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 7. No DELETE policy exists — an authorized manager cannot remove a
-- learner document file, matching the table's own "never hard delete"
-- policy (archiving the metadata row leaves the file retrievable, exactly
-- like an archived guardian link stays visible for restore elsewhere in
-- this schema).
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from storage.objects
    where bucket_id = 'learner-documents' and name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/doc1-birth-cert.pdf';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('deleting a learner document file is impossible even for an authorized manager (no DELETE policy)', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
