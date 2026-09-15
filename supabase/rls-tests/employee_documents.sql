-- Sebetsa Phase M — Documents & Employee Records: RLS/lifecycle/storage
-- checks.
--
--   supabase start
--   cat supabase/rls-tests/employee_documents.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000010a', 'Org M', 'active'),
  ('00000000-0000-0000-0000-00000000020a', 'Org N', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000011a', 'authenticated', 'authenticated', 'admin-m@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000012a', 'authenticated', 'authenticated', 'hr-m@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000013a', 'authenticated', 'authenticated', 'ops-m@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"operations_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000014a', 'authenticated', 'authenticated', 'site-m@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000015a', 'authenticated', 'authenticated', 'employee-m1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000016a', 'authenticated', 'authenticated', 'employee-m2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000011a', '00000000-0000-0000-0000-00000000010a', 'Admin', 'M', 'admin-m@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000012a', '00000000-0000-0000-0000-00000000010a', 'HR', 'M', 'hr-m@example.com', 'hr_user', 'active'),
  ('00000000-0000-0000-0000-00000000013a', '00000000-0000-0000-0000-00000000010a', 'Ops', 'M', 'ops-m@example.com', 'operations_manager', 'active'),
  ('00000000-0000-0000-0000-00000000014a', '00000000-0000-0000-0000-00000000010a', 'Site', 'M', 'site-m@example.com', 'site_manager', 'active'),
  ('00000000-0000-0000-0000-00000000015a', '00000000-0000-0000-0000-00000000010a', 'Emp', 'One', 'employee-m1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000016a', '00000000-0000-0000-0000-00000000010a', 'Emp', 'Two', 'employee-m2@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000011a","app_metadata":{"role":"organization_administrator"}}';

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000017a', '00000000-0000-0000-0000-00000000010a', '00000000-0000-0000-0000-00000000015a', 'M001', 'Emp', 'One', current_date),
  ('00000000-0000-0000-0000-00000000018a', '00000000-0000-0000-0000-00000000010a', '00000000-0000-0000-0000-00000000016a', 'M002', 'Emp', 'Two', current_date);

reset role;
reset request.jwt.claims;
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000019a', '00000000-0000-0000-0000-00000000020a', 'N001', 'Other', 'TenantEmployee', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000011a","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- create_document_upload_slot: cross-tenant, self-service, validation.

do $$
begin
  begin
    perform public.create_document_upload_slot('00000000-0000-0000-0000-00000000019a', 'certificate', 'cert.pdf', 'application/pdf', 1000, null);
    raise exception 'SECURITY_FAILURE: upload slot created for a cross-tenant employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: upload slot blocked for a cross-tenant employee (%)', sqlerrm;
  end;

  begin
    perform public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'certificate', 'cert.exe', 'application/x-msdownload', 1000, null);
    raise exception 'SECURITY_FAILURE: upload slot created with a disallowed MIME type';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: upload slot blocked for a disallowed MIME type (%)', sqlerrm;
  end;

  begin
    perform public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'certificate', 'cert.pdf', 'application/pdf', 999999999, null);
    raise exception 'SECURITY_FAILURE: upload slot created for an oversized file';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: upload slot blocked for an oversized file (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000016a","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'certificate', 'cert.pdf', 'application/pdf', 1000, null);
    raise exception 'SECURITY_FAILURE: employee-m2 uploaded a document for employee-m1';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from uploading a document for another employee (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000015a","app_metadata":{"role":"employee"}}';

do $$
declare
  v_doc public.employee_documents;
  v_medical public.employee_documents;
begin
  select * into v_doc from public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'certificate', 'first aid.pdf', 'application/pdf', 500000, current_date + 30);
  if v_doc.status <> 'uploaded' then raise exception 'FAIL: expected status=uploaded, got %', v_doc.status; end if;
  if v_doc.storage_path !~ ('^' || '00000000-0000-0000-0000-00000000010a' || '/' || '00000000-0000-0000-0000-00000000017a' || '/') then
    raise exception 'FAIL: storage_path does not have the expected tenant/employee prefix: %', v_doc.storage_path;
  end if;
  raise notice 'PASS: self-service upload slot creation succeeds with a server-generated tenant/employee-prefixed path';

  select * into v_medical from public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'medical', 'note.pdf', 'application/pdf', 1000, null);
  raise notice 'PASS: employee can upload their own medical document (id: %)', v_medical.id;
end $$;

-- ---------------------------------------------------------------------------
-- Visibility: site_manager (can_manage_operations tier, NOT
-- can_manage_employees) sees nothing; operations_manager sees the
-- non-sensitive doc but not the medical one; hr_user sees both.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000014a","app_metadata":{"role":"site_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a';
  if v_count <> 0 then raise exception 'FAIL: site_manager (operational tier, not HR tier) could read employee documents, got % rows', v_count; end if;
  raise notice 'PASS: site_manager (can_manage_operations, not can_manage_employees) sees zero employee documents';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000013a","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'certificate';
  if v_count <> 1 then raise exception 'FAIL: operations_manager (can_manage_employees tier) should see the non-sensitive document, got % rows', v_count; end if;

  select count(*) into v_count from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'medical';
  if v_count <> 0 then raise exception 'FAIL: operations_manager should NOT see the medical document, got % rows', v_count; end if;
  raise notice 'PASS: operations_manager sees non-sensitive documents but not medical/disciplinary ones';
end $$;

-- P1 remediation regression (docs/PRODUCTION_READINESS_AUDIT.md, storage
-- sensitivity-tier fix): the same restriction must hold at the
-- storage.objects layer, not just the metadata table — an
-- operations_manager must not be able to read the medical document's
-- bytes by going directly through the Storage API/table even though the
-- metadata query above correctly hides the row. The path is fetched as
-- the connecting superuser (bypasses RLS — not the property under test)
-- and stashed in a session GUC, since operations_manager's own RLS-scoped
-- lookup on employee_documents can't see this row either.
reset role;
reset request.jwt.claims;
do $$
declare v_path text;
begin
  select storage_path into v_path from public.employee_documents
  where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'medical';
  if v_path is null then raise exception 'test setup error: medical document storage_path not found'; end if;
  perform set_config('app.medical_storage_path', v_path, true);
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000013a","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from storage.objects
  where bucket_id = 'employee-documents' and name = current_setting('app.medical_storage_path', true);
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: operations_manager read the medical document object directly via storage.objects (% rows)', v_count; end if;
  raise notice 'PASS: operations_manager cannot read the medical document via storage.objects either';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000012a","app_metadata":{"role":"hr_user"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'medical';
  if v_count <> 1 then raise exception 'FAIL: hr_user should see the medical document, got % rows', v_count; end if;
  raise notice 'PASS: hr_user sees medical/disciplinary documents';
end $$;

-- ---------------------------------------------------------------------------
-- verify_document: unauthorized blocked, authorized succeeds, repeated blocked.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000015a","app_metadata":{"role":"employee"}}';

do $$
declare v_doc_id uuid;
begin
  select id into v_doc_id from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'certificate';
  begin
    perform public.verify_document(v_doc_id, true);
    raise exception 'SECURITY_FAILURE: employee verified their own document';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from verifying their own document (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000012a","app_metadata":{"role":"hr_user"}}';

do $$
declare v_doc_id uuid; v_doc public.employee_documents;
begin
  select id into v_doc_id from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'certificate';
  select * into v_doc from public.verify_document(v_doc_id, true, 'looks good');
  if v_doc.status <> 'verified' then raise exception 'FAIL: expected verified, got %', v_doc.status; end if;
  if v_doc.verified_by <> '00000000-0000-0000-0000-00000000012a' then raise exception 'FAIL: verified_by not server-derived correctly'; end if;
  raise notice 'PASS: hr_user can verify a document; verified_by/verified_at are server-derived';

  begin
    perform public.verify_document(v_doc_id, true);
    raise exception 'SECURITY_FAILURE: a second verify_document call on an already-verified document succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated verification on an already-decided document is blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- replace_document: versioning preserves history, never destructive.

do $$
declare
  v_old_id uuid;
  v_new public.employee_documents;
  v_old_status public.document_status;
  v_count int;
begin
  select id into v_old_id from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a' and document_type = 'certificate';
  select * into v_new from public.replace_document(v_old_id, 'first aid v2.pdf', 'application/pdf', 600000, current_date + 60);

  if v_new.version <> 2 then raise exception 'FAIL: expected version 2, got %', v_new.version; end if;
  if v_new.supersedes_document_id <> v_old_id then raise exception 'FAIL: supersedes_document_id not set correctly'; end if;

  select status into v_old_status from public.employee_documents where id = v_old_id;
  if v_old_status <> 'archived' then raise exception 'FAIL: expected old document archived, got %', v_old_status; end if;

  select count(*) into v_count from public.employee_documents where id = v_old_id;
  if v_count <> 1 then raise exception 'FAIL: replace_document destroyed the old document row instead of archiving it'; end if;
  raise notice 'PASS: replace_document creates a new version, archives (never deletes) the old one, and preserves the supersession link';
end $$;

-- ---------------------------------------------------------------------------
-- sync_expired_documents: flips a past-expiry verified document, never
-- deletes. Uses a fresh document (the original 'certificate' one was
-- already archived by replace_document above, so nothing is left in
-- 'verified' status for it) — verify it first, then age it past expiry.

do $$
declare
  v_doc public.employee_documents;
  v_status public.document_status;
  v_count_before int;
  v_count_after int;
begin
  select * into v_doc from public.create_document_upload_slot('00000000-0000-0000-0000-00000000017a', 'qualification', 'diploma.pdf', 'application/pdf', 1000, current_date - 1);

  reset role;
  reset request.jwt.claims;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000012a","app_metadata":{"role":"hr_user"}}';

  perform public.verify_document(v_doc.id, true);

  select count(*) into v_count_before from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a';

  perform public.sync_expired_documents('00000000-0000-0000-0000-00000000010a');

  select status into v_status from public.employee_documents where id = v_doc.id;
  if v_status <> 'expired' then raise exception 'FAIL: expected expired, got %', v_status; end if;

  select count(*) into v_count_after from public.employee_documents where employee_id = '00000000-0000-0000-0000-00000000017a';
  if v_count_after <> v_count_before then raise exception 'FAIL: sync_expired_documents changed the row count (deleted or duplicated something), before=% after=%', v_count_before, v_count_after; end if;
  raise notice 'PASS: sync_expired_documents flips a past-expiry verified document to expired without deleting anything';
end $$;

-- ---------------------------------------------------------------------------
-- Storage object policies: direct table-level validation of the same
-- tenant/employee path-prefix rule the Storage API enforces at upload time.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000016a","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    insert into storage.objects (bucket_id, name) values ('employee-documents', '00000000-0000-0000-0000-00000000010a/00000000-0000-0000-0000-00000000017a/malicious.pdf');
    raise exception 'SECURITY_FAILURE: employee-m2 wrote a storage object under employee-m1''s path prefix';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: storage.objects blocks a write under another employee''s path prefix (%)', sqlerrm;
  end;
end $$;

-- Verified via the INSERT's own row_count, not a follow-up SELECT: this
-- object is created directly (not via create_document_upload_slot()), so
-- it has no matching employee_documents row, and P1 remediation
-- (docs/PRODUCTION_READINESS_AUDIT.md, storage sensitivity-tier fix) made
-- the storage.objects SELECT policy join on that row to determine
-- document_type sensitivity — correctly failing closed for an object with
-- no metadata counterpart, which never happens in the real upload flow.
do $$
declare v_rows int;
begin
  insert into storage.objects (bucket_id, name) values ('employee-documents', '00000000-0000-0000-0000-00000000010a/00000000-0000-0000-0000-00000000018a/own-file.pdf');
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then raise exception 'FAIL: employee-m2 could not write a storage object under their own path prefix'; end if;
  raise notice 'PASS: an employee can write a storage object under their own tenant/employee path prefix';
end $$;

reset role;
reset request.jwt.claims;

rollback;
