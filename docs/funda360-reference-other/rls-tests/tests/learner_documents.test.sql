-- Regression suite for the `learner_documents` table — previously entirely
-- untested (flagged as a gap in the Phase 1 audit; the table's own
-- migration comment explicitly defers self/guardian access as an open
-- question, so this suite tests the staff-only access it actually ships
-- with, not a broader model it doesn't). Uses learner
-- 11110000-0000-0000-0000-000000000001 (School A, enrolled in class
-- cccc1111...0001 — see 05_learner_fixtures.sql) and users from
-- 02_fixtures.sql + 04_employee_fixtures.sql.

-- ---------------------------------------------------------------------------
-- 1. Authorized manager (principal) can upload/insert a document for a
-- School A learner.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name)
  values ('dc111111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'birth_certificate', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/birth-cert.pdf', 'birth-cert.pdf');
  select count(*) into v_count from public.learner_documents where id = 'dc111111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('an authorized manager can upload a document for a learner in their school', v_count = 1, 'rows created: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Authorized manager can then read it back.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id = 'dc111111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('an authorized manager can read a document uploaded by a different authorized manager', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher (no learner.view at all in this pilot's role model) cannot
-- read a learner's documents, even for a learner in their own school.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id = 'dc111111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher cannot read a learner''s documents (no learner.view in this role model)', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant: School B's owner cannot see School A's learner document.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_documents where id = 'dc111111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant learner documents remain invisible', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant write is rejected by the tenant-consistency trigger even
-- when the caller supplies their own (correct) school_id — the trigger
-- checks the REFERENCED LEARNER's school_id, not just the caller's own.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_documents (school_id, learner_id, document_type, file_url)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11110000-0000-0000-0000-000000000001', 'other', 'spoofed.pdf');
    call test_util.record('cross-tenant learner_id reference is rejected by the tenant-consistency trigger', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cross-tenant learner_id reference is rejected by the tenant-consistency trigger',
      v_error like '%insufficient_privilege%' or v_error like '%row-level security%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Unauthorized role cannot upload a document at all.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_documents (school_id, learner_id, document_type, file_url)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'other', 'unauthorized.pdf');
    call test_util.record('a teacher cannot upload a learner document', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot upload a learner document', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. Archiving (active=false) is the only supported "removal" — an
-- authorized manager can do it...
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.learner_documents set active = false where id = 'dc111111-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('an authorized manager can archive a learner document', v_updated = 1, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 8. ...and no DELETE policy exists — hard delete is impossible even for an
-- authorized manager, matching every other domain's never-hard-delete
-- pattern (and matching documentService.ts, which only ever calls
-- update({active:false}), never .delete()).
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.learner_documents where id = 'dc111111-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a learner document is impossible even for an authorized manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
