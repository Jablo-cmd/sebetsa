-- Regression suite for FND-SIS-009 (versioning half — expiry_date was
-- already covered by document_expiry_alerts.test.sql):
-- 20260829170000_document_versioning.sql's supersedes_document_id +
-- learner_documents_archive_superseded() trigger.
--
-- Uses School A, learner A1 (11110000...0001 — 05_learner_fixtures.sql)
-- and A2 (11110000...0002, also School A, not enrolled anywhere — used
-- only as the "different learner" case). Creates its own dedicated
-- document rows (a fresh id prefix, `de` for "document, extended") rather
-- than reusing learner_documents.test.sql's own dc111111... row — that
-- file mutates its row's `active` state as its own tests progress, so
-- depending on its end state here would make this suite's outcome depend
-- on file execution order. No new learner is created (unlike
-- attendance_alerts.test.sql/fee_overdue_reminders.test.sql/document_
-- expiry_alerts.test.sql's own isolation fixtures) — learner_documents
-- carries no exact-count assertion anywhere in this suite, so reusing
-- existing learners is safe here.

-- ---------------------------------------------------------------------------
-- 1. school_owner uploads an original document, then a renewal that
-- supersedes it — the original is auto-archived in the same transaction.
do $$
declare v_original_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name) values
    ('de000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'passport', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/passport-old.pdf', 'passport-old.pdf');

  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name, supersedes_document_id) values
    ('de000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'passport', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/passport-new.pdf', 'passport-new.pdf', 'de000000-0000-0000-0000-000000000001');

  execute 'reset role';

  select active into v_original_active from public.learner_documents where id = 'de000000-0000-0000-0000-000000000001';
  call test_util.record('uploading a renewal auto-archives the document it supersedes', v_original_active = false, 'active=' || v_original_active);
end $$;

-- ---------------------------------------------------------------------------
-- 2. The new document itself stays active, and correctly records what it
-- supersedes.
do $$
declare v_new_active boolean;
declare v_supersedes uuid;
begin
  select active, supersedes_document_id into v_new_active, v_supersedes from public.learner_documents where id = 'de000000-0000-0000-0000-000000000002';
  call test_util.record('the new (superseding) document itself stays active', v_new_active = true, 'active=' || v_new_active);
  call test_util.record('the new document records what it supersedes', v_supersedes = 'de000000-0000-0000-0000-000000000001', 'supersedes_document_id=' || coalesce(v_supersedes::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. supersedes_document_id must reference a document belonging to the
-- SAME learner — cross-learner references are rejected outright.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_documents (school_id, learner_id, document_type, file_url, supersedes_document_id) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002', 'passport', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000002/cross-learner.pdf', 'de000000-0000-0000-0000-000000000001');
    call test_util.record('a cross-learner supersedes_document_id is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a cross-learner supersedes_document_id is rejected', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. A plain upload with no supersedes_document_id is unaffected — no
-- other document gets archived as a side effect.
do $$
declare v_untouched_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name) values
    ('de000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'medical_certificate', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-000000000001/unrelated.pdf', 'unrelated.pdf');
  execute 'reset role';

  select active into v_untouched_active from public.learner_documents where id = 'de000000-0000-0000-0000-000000000002';
  call test_util.record('an unrelated plain upload does not archive anything else', v_untouched_active = true, 'active=' || v_untouched_active);
end $$;
