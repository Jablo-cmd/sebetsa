-- Sebetsa Phase M — Documents & Employee Records, migration 2 of 2.
--
-- SECURITY DEFINER RPCs for the upload/verify/replace workflow. The actual
-- file bytes are uploaded directly to Supabase Storage by the client
-- (governed by the storage.objects policies in the previous migration) —
-- these RPCs only manage the metadata row and hand back the exact path
-- the client must upload to, so the path is never client-chosen.

create or replace function public.create_document_upload_slot(
  p_employee_id uuid,
  p_document_type public.document_type,
  p_file_name text,
  p_mime_type text,
  p_file_size_bytes integer,
  p_expiry_date date default null
)
returns public.employee_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_own boolean;
  v_result public.employee_documents;
  v_safe_file_name text;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  select exists(select 1 from public.employees where id = p_employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_employees(v_tenant_id)) then
    raise exception 'insufficient_privilege: cannot upload a document for this employee';
  end if;

  -- Allow-list check on the client-declared MIME type. Note (per the
  -- architecture principle "do not trust client-supplied MIME types
  -- alone"): this is a necessary but not sufficient control — genuine
  -- magic-byte content sniffing would need an Edge Function inspecting
  -- the uploaded bytes after the fact, which is explicitly deferred here
  -- rather than fabricated as a false sense of security. The size cap and
  -- MIME allow-list are enforced by the table's own CHECK constraints too
  -- (defense in depth against a caller bypassing this RPC's checks via a
  -- direct... there is no direct INSERT policy, so this is the only path).
  if p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception 'invalid_file_type: only PDF, JPEG, or PNG files are accepted';
  end if;
  if p_file_size_bytes > 10485760 then
    raise exception 'file_too_large: maximum file size is 10MB';
  end if;

  -- Strip path separators from the filename before it becomes part of the
  -- storage path — a malicious filename must never let the object escape
  -- the {tenant}/{employee}/ prefix the storage policies check.
  v_safe_file_name := regexp_replace(p_file_name, '[^a-zA-Z0-9._-]', '_', 'g');

  insert into public.employee_documents (
    tenant_id, employee_id, document_type, file_name, mime_type, file_size_bytes,
    storage_path, expiry_date, uploaded_by
  ) values (
    v_tenant_id, p_employee_id, p_document_type, p_file_name, p_mime_type, p_file_size_bytes,
    v_tenant_id::text || '/' || p_employee_id::text || '/' || gen_random_uuid()::text || '-' || v_safe_file_name,
    p_expiry_date, auth.uid()
  )
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'document_upload_slot_created', 'employee_documents', v_result.id, null, jsonb_build_object('document_type', p_document_type, 'file_name', p_file_name));

  return v_result;
end;
$$;

comment on function public.create_document_upload_slot(uuid, public.document_type, text, text, integer, date) is
  'Creates the metadata row and returns the exact storage_path the client must upload the file bytes to (via supabase.storage.from(''employee-documents'').upload(path, file)) — the path is server-generated, never client-chosen, closing off path traversal/collision.';

revoke execute on function public.create_document_upload_slot(uuid, public.document_type, text, text, integer, date) from public, anon;
grant execute on function public.create_document_upload_slot(uuid, public.document_type, text, text, integer, date) to authenticated;

-- ---------------------------------------------------------------------------
-- verify_document: can_manage_employees() tier only.

create or replace function public.verify_document(p_document_id uuid, p_approve boolean, p_review_notes text default null)
returns public.employee_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_document public.employee_documents;
begin
  select * into v_document from public.employee_documents where id = p_document_id for update;
  if not found then
    raise exception 'not_found: no document %', p_document_id;
  end if;

  if not public.can_manage_employees(v_document.tenant_id) then
    raise exception 'insufficient_privilege: cannot verify documents for this tenant';
  end if;

  if v_document.status not in ('uploaded', 'pending_review') then
    raise exception 'invalid_transition: only an uploaded/pending_review document can be verified or rejected (current status: %)', v_document.status;
  end if;

  update public.employee_documents
  set status = case when p_approve then 'verified' else 'rejected' end::public.document_status,
      verified_by = auth.uid(),
      verified_at = now(),
      review_notes = p_review_notes
  where id = p_document_id
  returning * into v_document;

  perform public.write_audit_log(
    v_document.tenant_id, auth.uid(), case when p_approve then 'document_verified' else 'document_rejected' end,
    'employee_documents', v_document.id, null, jsonb_build_object('review_notes', p_review_notes)
  );

  return v_document;
end;
$$;

revoke execute on function public.verify_document(uuid, boolean, text) from public, anon;
grant execute on function public.verify_document(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- replace_document: uploads a new version, archives the old one. Never a
-- destructive overwrite — full history preserved via supersedes_document_id.

create or replace function public.replace_document(
  p_old_document_id uuid,
  p_file_name text,
  p_mime_type text,
  p_file_size_bytes integer,
  p_expiry_date date default null
)
returns public.employee_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.employee_documents;
  v_is_own boolean;
  v_new public.employee_documents;
  v_safe_file_name text;
begin
  select * into v_old from public.employee_documents where id = p_old_document_id for update;
  if not found then
    raise exception 'not_found: no document %', p_old_document_id;
  end if;

  select exists(select 1 from public.employees where id = v_old.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_employees(v_old.tenant_id)) then
    raise exception 'insufficient_privilege: cannot replace this document';
  end if;

  if p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception 'invalid_file_type: only PDF, JPEG, or PNG files are accepted';
  end if;
  if p_file_size_bytes > 10485760 then
    raise exception 'file_too_large: maximum file size is 10MB';
  end if;

  v_safe_file_name := regexp_replace(p_file_name, '[^a-zA-Z0-9._-]', '_', 'g');

  update public.employee_documents set status = 'archived' where id = p_old_document_id;

  insert into public.employee_documents (
    tenant_id, employee_id, document_type, file_name, mime_type, file_size_bytes,
    storage_path, version, supersedes_document_id, expiry_date, uploaded_by
  ) values (
    v_old.tenant_id, v_old.employee_id, v_old.document_type, p_file_name, p_mime_type, p_file_size_bytes,
    v_old.tenant_id::text || '/' || v_old.employee_id::text || '/' || gen_random_uuid()::text || '-' || v_safe_file_name,
    v_old.version + 1, p_old_document_id, coalesce(p_expiry_date, v_old.expiry_date), auth.uid()
  )
  returning * into v_new;

  perform public.write_audit_log(v_new.tenant_id, auth.uid(), 'document_replaced', 'employee_documents', v_new.id, jsonb_build_object('supersedes', p_old_document_id), jsonb_build_object('version', v_new.version));

  return v_new;
end;
$$;

revoke execute on function public.replace_document(uuid, text, text, integer, date) from public, anon;
grant execute on function public.replace_document(uuid, text, text, integer, date) to authenticated;

-- ---------------------------------------------------------------------------
-- sync_expired_documents: manually triggered (cron-ready, not scheduled —
-- same posture as Phase K's task recurrence/escalation). Flips a verified
-- document past its expiry_date to 'expired' for operational visibility
-- (expiring-soon/expired dashboards), never deletes it.

create or replace function public.sync_expired_documents(p_tenant_id uuid)
returns setof public.employee_documents
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_employees(p_tenant_id) then
    raise exception 'insufficient_privilege: cannot sync documents for this tenant';
  end if;

  return query
  update public.employee_documents
  set status = 'expired'
  where tenant_id = p_tenant_id
    and status = 'verified'
    and expiry_date is not null
    and expiry_date < current_date
  returning *;
end;
$$;

comment on function public.sync_expired_documents(uuid) is
  'Manually triggered from the UI — cron-ready, not scheduled. Only affects verified documents past expiry_date; never deletes anything.';

revoke execute on function public.sync_expired_documents(uuid) from public, anon;
grant execute on function public.sync_expired_documents(uuid) to authenticated;
