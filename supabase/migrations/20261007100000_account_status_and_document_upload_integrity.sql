-- 1. Deactivated accounts are locked out by the database, not just the UI.
--    Until now deactivation only set profiles.status; the user's JWT kept
--    working against every RLS policy. current_tenant_id() (used by nearly
--    every tenant policy) now returns NULL for a non-active profile, and
--    is_platform_admin() is false for one. A user can still read their own
--    profile row, which is how the app shows "Account deactivated".
-- 2. admin_set_user_status(): the only way to change an account status. It
--    also bans/unbans the auth user (no new tokens), is audited as a security
--    event, and a user can never change their own status.
-- 3. Document uploads: replace_document() remembers the previous status of
--    the archived version, and cancel_document_upload() lets the uploader
--    discard a slot whose file never reached storage (restoring the previous
--    version on a replacement), so a failed upload leaves no phantom record.

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid() and status = 'active'
$$;

-- security definer so it can read profiles without re-entering the profiles
-- RLS policies (which themselves call is_platform_admin()). A user with no
-- profile row is not blocked here (bootstrap accounts); a non-active one is.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'platform_administrator'
    and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.status <> 'active')
$$;

-- Status changes go through admin_set_user_status() only. Supabase gives
-- `authenticated` a blanket table-level UPDATE that covers every column, so a
-- column revoke alone does nothing: drop the table-level grant and re-grant
-- only the self-service contact columns (role/tenant/status/email stay behind
-- their RPCs and triggers, now also behind privileges).
revoke update on public.profiles from authenticated;
grant update (first_name, last_name, phone, avatar_url) on public.profiles to authenticated;

insert into public.sod_rules (rule_key, description) values
  ('user.status', 'A user cannot activate or deactivate their own account.');

create or replace function public.admin_set_user_status(p_user_id uuid, p_status public.profile_status)
returns public.profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target public.profiles;
  v_actor_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
  v_previous public.profile_status;
begin
  select * into v_target from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'not_found: no profile for user %', p_user_id;
  end if;

  if not public.can_manage_profiles(v_target.tenant_id) then
    raise exception 'insufficient_privilege: cannot manage this user''s tenant';
  end if;

  perform public.assert_separation_of_duties('user.status', array[p_user_id]);

  if v_target.role in ('platform_administrator', 'organization_administrator')
     and v_actor_role not in ('platform_administrator', 'organization_administrator') then
    raise exception 'insufficient_privilege: cannot change the status of this user';
  end if;
  if v_target.role = 'platform_administrator' and v_actor_role <> 'platform_administrator' then
    raise exception 'insufficient_privilege: cannot change the status of this user';
  end if;

  v_previous := v_target.status;
  update public.profiles set status = p_status where id = p_user_id returning * into v_target;

  update auth.users
     set banned_until = case when p_status = 'active' then null else 'infinity'::timestamptz end
   where id = p_user_id;

  perform public.write_audit_log(
    v_target.tenant_id, auth.uid(), 'user_status_changed', 'profiles', p_user_id,
    jsonb_build_object('status', v_previous), jsonb_build_object('status', p_status)
  );

  return v_target;
end;
$$;

revoke execute on function public.admin_set_user_status(uuid, public.profile_status) from public, anon;
grant execute on function public.admin_set_user_status(uuid, public.profile_status) to authenticated, service_role;

-- Document upload integrity.
alter table public.employee_documents
  add column status_before_archive public.document_status;

comment on column public.employee_documents.status_before_archive is
  'Status the version had before replace_document() archived it, so cancelling the replacement can restore it.';

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

  if v_old.status = 'archived' then
    raise exception 'invalid_transition: this version has already been replaced';
  end if;

  if p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception 'invalid_file_type: only PDF, JPEG, or PNG files are accepted';
  end if;
  if p_file_size_bytes > 10485760 then
    raise exception 'file_too_large: maximum file size is 10MB';
  end if;

  v_safe_file_name := regexp_replace(p_file_name, '[^a-zA-Z0-9._-]', '_', 'g');

  update public.employee_documents
     set status = 'archived', status_before_archive = v_old.status
   where id = p_old_document_id;

  insert into public.employee_documents (
    tenant_id, employee_id, document_type, file_name, mime_type, file_size_bytes,
    storage_path, version, supersedes_document_id, expiry_date, uploaded_by
  ) values (
    v_old.tenant_id, v_old.employee_id, v_old.document_type, p_file_name, p_mime_type, p_file_size_bytes,
    v_old.tenant_id::text || '/' || v_old.employee_id::text || '/' || gen_random_uuid()::text || '-' || v_safe_file_name,
    v_old.version + 1, p_old_document_id, coalesce(p_expiry_date, v_old.expiry_date), auth.uid()
  )
  returning * into v_new;

  perform public.write_audit_log(
    v_new.tenant_id, auth.uid(), 'document_replaced', 'employee_documents', v_new.id,
    jsonb_build_object('supersedes', p_old_document_id), jsonb_build_object('version', v_new.version)
  );

  return v_new;
end;
$$;

create or replace function public.cancel_document_upload(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.employee_documents;
begin
  select * into v_doc from public.employee_documents where id = p_document_id for update;
  if not found then
    raise exception 'not_found: no document %', p_document_id;
  end if;

  if v_doc.uploaded_by is distinct from auth.uid() then
    raise exception 'insufficient_privilege: only the uploader can cancel an upload';
  end if;
  if v_doc.status <> 'uploaded' or v_doc.verified_by is not null then
    raise exception 'invalid_transition: only a fresh, unreviewed upload can be cancelled';
  end if;
  if v_doc.created_at < now() - interval '15 minutes' then
    raise exception 'invalid_transition: this upload can no longer be cancelled';
  end if;

  if v_doc.supersedes_document_id is not null then
    update public.employee_documents
       set status = coalesce(status_before_archive, 'uploaded'), status_before_archive = null
     where id = v_doc.supersedes_document_id and status = 'archived';
  end if;

  delete from public.employee_documents where id = p_document_id;

  perform public.write_audit_log(
    v_doc.tenant_id, auth.uid(), 'document_upload_cancelled', 'employee_documents', p_document_id,
    to_jsonb(v_doc), null
  );
end;
$$;

revoke execute on function public.cancel_document_upload(uuid) from public, anon;
grant execute on function public.cancel_document_upload(uuid) to authenticated, service_role;
revoke execute on function public.replace_document(uuid, text, text, integer, date) from public, anon;
grant execute on function public.replace_document(uuid, text, text, integer, date) to authenticated, service_role;


-- Separation of duties applies to a real review decision (an unreviewed
-- document becoming verified/rejected), not to restoring a previously
-- reviewed version when a replacement upload is cancelled.
create or replace function public.sod_guard_employee_documents()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status in ('uploaded', 'pending_review')
     and ((new.status is distinct from old.status and new.status in ('verified', 'rejected'))
          or (new.verified_by is distinct from old.verified_by and new.verified_by is not null)) then
    perform public.assert_separation_of_duties(
      'document.verify', array[new.uploaded_by, public.employee_profile_id(new.employee_id)]);
  end if;
  return null;
end;
$$;

-- admin_create_user calls pgcrypto (crypt, gen_salt, gen_random_bytes). On Supabase
-- pgcrypto lives in the `extensions` schema, which a pinned search_path of
-- `public, auth` does not include — user creation and employee login
-- provisioning failed with "function gen_random_bytes(integer) does not exist".
-- Same body, with `extensions` added to the pinned search_path.
CREATE OR REPLACE FUNCTION public.admin_create_user(p_email text, p_first_name text, p_last_name text, p_phone text, p_role user_role, p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid, temporary_password text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  v_effective_tenant uuid;
  v_new_user_id uuid;
  v_temp_password text;
begin
  if public.is_platform_admin() then
    v_effective_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  else
    v_effective_tenant := public.current_tenant_id();
  end if;

  if not public.can_assign_role(p_role, null) then
    raise exception 'insufficient_privilege: cannot create a user with role %', p_role;
  end if;

  if exists (select 1 from auth.users u where u.email = p_email) then
    raise exception 'email_taken: % is already registered', p_email;
  end if;

  v_new_user_id := gen_random_uuid();
  v_temp_password := encode(gen_random_bytes(18), 'base64');

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_new_user_id, 'authenticated', 'authenticated', p_email,
    crypt(v_temp_password, gen_salt('bf')), now(),
    jsonb_build_object(
      'provider', 'email', 'providers', jsonb_build_array('email'),
      'role', p_role, 'tenant_id', v_effective_tenant
    ),
    jsonb_build_object('first_name', p_first_name, 'last_name', p_last_name),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_new_user_id,
    jsonb_build_object('sub', v_new_user_id::text, 'email', p_email),
    'email', v_new_user_id::text, now(), now(), now()
  );

  insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status)
  values (v_new_user_id, v_effective_tenant, p_first_name, p_last_name, p_email, p_phone, p_role, 'active');

  return query select v_new_user_id, v_temp_password;
end;
$function$

;

-- Authorship is server-derived. task_evidence.submitted_by is documented as
-- "server-derived" but nothing derived it (evidence was stored with no author),
-- and other columns that record "who did this" were whatever the client sent.
-- For client requests (auth.uid() is set) the actor column is now always the
-- caller; service-role/system writes (auth.uid() is NULL) keep what they pass.
create or replace function public.set_actor_column()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], auth.uid()));
  elsif tg_table_name = 'attendance_records' and new.status is distinct from old.status then
    -- A manually marked/changed status is attributed to whoever changed it.
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], auth.uid()));
  end if;
  return new;
end;
$$;

create trigger task_evidence_set_actor before insert on public.task_evidence
  for each row execute function public.set_actor_column('submitted_by');
create trigger task_comments_set_actor before insert on public.task_comments
  for each row execute function public.set_actor_column('author_id');
create trigger tasks_set_actor before insert on public.tasks
  for each row execute function public.set_actor_column('created_by');
create trigger compliance_requirements_set_actor before insert on public.compliance_requirements
  for each row execute function public.set_actor_column('created_by');
create trigger inventory_movements_set_actor before insert on public.inventory_movements
  for each row execute function public.set_actor_column('performed_by');
create trigger attendance_records_set_actor before insert or update on public.attendance_records
  for each row execute function public.set_actor_column('recorded_by');

revoke execute on function public.set_actor_column() from public, anon, authenticated;
