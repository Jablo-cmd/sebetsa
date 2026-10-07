-- Account lifecycle and upload integrity: server-side lockout of inactive
-- accounts, admin_set_user_status(), cancel_document_upload().

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000f0301', 'Org H', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(),
       jsonb_build_object('role', u.role), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0311', 'admin-h@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0312', 'hr-h@example.com', 'hr_user'),
  ('00000000-0000-0000-0000-0000000f0313', 'employee-h@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0314', 'platform-h@example.com', 'platform_administrator'),
  ('00000000-0000-0000-0000-0000000f0315', 'ops-h@example.com', 'operations_manager')
) as u(id, email, role);

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
select p.id::uuid, p.tenant::uuid, p.fname, 'H', p.email, p.role::public.user_role, 'active'
from (values
  ('00000000-0000-0000-0000-0000000f0311', '00000000-0000-0000-0000-0000000f0301', 'Admin', 'admin-h@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0312', '00000000-0000-0000-0000-0000000f0301', 'Hr', 'hr-h@example.com', 'hr_user'),
  ('00000000-0000-0000-0000-0000000f0313', '00000000-0000-0000-0000-0000000f0301', 'Emp', 'employee-h@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0314', null, 'Platform', 'platform-h@example.com', 'platform_administrator'),
  ('00000000-0000-0000-0000-0000000f0315', '00000000-0000-0000-0000-0000000f0301', 'Ops', 'ops-h@example.com', 'operations_manager')
) as p(id, tenant, fname, email, role);

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0321', '00000000-0000-0000-0000-0000000f0301', 'Client H');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-0000000f0331', '00000000-0000-0000-0000-0000000f0301', '00000000-0000-0000-0000-0000000f0321', 'Site H');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-0000000f0341', '00000000-0000-0000-0000-0000000f0301', '00000000-0000-0000-0000-0000000f0313', 'H001', 'Emp', 'H', current_date);

-- ---------------------------------------------------------------------------
-- Deactivation is enforced by the database.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}';

do $$
declare v_sites int;
begin
  select count(*) into v_sites from public.sites;
  if v_sites <> 1 then raise exception 'FAIL: active employee should see their tenant site, saw %', v_sites; end if;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0311","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_row public.profiles; v_audit record;
begin
  begin
    update public.profiles set status = 'inactive' where id = '00000000-0000-0000-0000-0000000f0313';
    raise exception 'SECURITY_FAILURE: profiles.status was updated directly';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;

  begin
    perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0311', 'inactive');
    raise exception 'SECURITY_FAILURE: an administrator deactivated their own account';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'separation_of_duties%' then raise exception 'FAIL: expected separation_of_duties, got %', sqlerrm; end if;
  end;

  select * into v_row from public.admin_set_user_status('00000000-0000-0000-0000-0000000f0313', 'inactive');
  if v_row.status <> 'inactive' then raise exception 'FAIL: status not set (%)', v_row.status; end if;

  select category, actor_profile_id into v_audit from public.audit_log where action = 'user_status_changed' and entity_id = '00000000-0000-0000-0000-0000000f0313';
  if v_audit.category <> 'security' then raise exception 'FAIL: status change not audited as security (%)', v_audit.category; end if;
  raise notice 'PASS: status only changes via the RPC; self-change blocked; audited as security';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_banned timestamptz;
begin
  select banned_until into v_banned from auth.users where id = '00000000-0000-0000-0000-0000000f0313';
  if v_banned is distinct from 'infinity'::timestamptz then raise exception 'FAIL: auth user not banned (%)', v_banned; end if;
  raise notice 'PASS: deactivation bans the auth user (no new tokens)';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}';

do $$
declare v_sites int; v_own int;
begin
  select count(*) into v_sites from public.sites;
  if v_sites <> 0 then raise exception 'SECURITY_FAILURE: deactivated employee still reads tenant data (% sites)', v_sites; end if;
  select count(*) into v_own from public.profiles where id = auth.uid();
  if v_own <> 1 then raise exception 'FAIL: a deactivated user must still read their own profile (to see the notice), saw %', v_own; end if;
  raise notice 'PASS: a deactivated account loses tenant access immediately but can still read its own profile';
end $$;

-- Hierarchy: HR cannot deactivate an organisation administrator, but can an employee.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0312","app_metadata":{"role":"hr_user"}}';

do $$
begin
  begin
    perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0311', 'inactive');
    raise exception 'SECURITY_FAILURE: hr_user deactivated an organisation administrator';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'insufficient_privilege%' then raise exception 'FAIL: expected insufficient_privilege, got %', sqlerrm; end if;
  end;
  perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0313', 'active');
  raise notice 'PASS: hr_user cannot deactivate a more senior user but can reactivate an employee';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_banned timestamptz;
begin
  select banned_until into v_banned from auth.users where id = '00000000-0000-0000-0000-0000000f0313';
  if v_banned is not null then raise exception 'FAIL: reactivation did not lift the auth ban'; end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}';
do $$
declare v_sites int;
begin
  select count(*) into v_sites from public.sites;
  if v_sites <> 1 then raise exception 'FAIL: reactivated employee should regain access, saw % sites', v_sites; end if;
  raise notice 'PASS: reactivation restores access and lifts the auth ban';
end $$;

-- An inactive platform administrator is no longer a platform administrator; one with no profile row still is (bootstrap).
reset role;
reset request.jwt.claims;
do $$
declare v_before boolean; v_after boolean;
begin
  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0314","app_metadata":{"role":"platform_administrator"}}', true);
  select public.is_platform_admin() into v_before;
  update public.profiles set status = 'inactive' where id = '00000000-0000-0000-0000-0000000f0314';
  select public.is_platform_admin() into v_after;
  if not v_before or v_after then raise exception 'FAIL: is_platform_admin before=% after=%', v_before, v_after; end if;
  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f09ff","app_metadata":{"role":"platform_administrator"}}', true);
  select public.is_platform_admin() into v_after;
  if not v_after then raise exception 'FAIL: a platform administrator with no profile row (bootstrap) must still work'; end if;
  raise notice 'PASS: inactive platform administrators are locked out; bootstrap accounts without a profile still work';
end $$;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Document upload integrity.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}';

do $$
declare v_doc public.employee_documents; v_count int;
begin
  select * into v_doc from public.create_document_upload_slot('00000000-0000-0000-0000-0000000f0341', 'certificate', 'a.pdf', 'application/pdf', 1000, null);

  begin
    perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0312","app_metadata":{"role":"hr_user"}}', true);
    perform public.cancel_document_upload(v_doc.id);
    raise exception 'SECURITY_FAILURE: someone other than the uploader cancelled an upload';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'insufficient_privilege%' then raise exception 'FAIL: expected insufficient_privilege, got %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}', true);
  perform public.cancel_document_upload(v_doc.id);
  select count(*) into v_count from public.employee_documents where id = v_doc.id;
  if v_count <> 0 then raise exception 'FAIL: cancelled upload still present'; end if;
  raise notice 'PASS: only the uploader can cancel a slot, and the phantom record is removed';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_old uuid := gen_random_uuid(); v_new public.employee_documents; v_status public.document_status;
begin
  insert into public.employee_documents (id, tenant_id, employee_id, document_type, file_name, mime_type, file_size_bytes, storage_path, status, uploaded_by, verified_by, verified_at)
  values (v_old, '00000000-0000-0000-0000-0000000f0301', '00000000-0000-0000-0000-0000000f0341', 'certificate', 'orig.pdf', 'application/pdf', 10, 'p/orig', 'verified',
          '00000000-0000-0000-0000-0000000f0313', '00000000-0000-0000-0000-0000000f0312', now());

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0313","app_metadata":{"role":"employee"}}', true);
  select * into v_new from public.replace_document(v_old, 'new.pdf', 'application/pdf', 20, null);
  select status into v_status from public.employee_documents where id = v_old;
  if v_status <> 'archived' then raise exception 'FAIL: old version not archived (%)', v_status; end if;

  begin
    perform public.replace_document(v_old, 'again.pdf', 'application/pdf', 20, null);
    raise exception 'SECURITY_FAILURE: an already-replaced version was replaced again';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got %', sqlerrm; end if;
  end;

  perform public.cancel_document_upload(v_new.id);
  select status into v_status from public.employee_documents where id = v_old;
  if v_status <> 'verified' then raise exception 'FAIL: cancelling the replacement should restore the previous version as verified, got %', v_status; end if;
  raise notice 'PASS: cancelling a replacement restores the previous version''s status';
end $$;

-- ---------------------------------------------------------------------------
-- User creation and login provisioning actually work on a Supabase-layout
-- database (pgcrypto in the `extensions` schema).
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, email, employment_start_date) values
  ('00000000-0000-0000-0000-0000000f0342', '00000000-0000-0000-0000-0000000f0301', 'H002', 'Prov', 'Ision', 'provision-h@example.com', current_date);

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0311","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_user uuid; v_password text; v_count int; v_has_hash boolean;
begin
  select user_id, temporary_password into v_user, v_password from public.admin_create_user('created-h@example.com', 'Created', 'H', '', 'site_manager');
  if v_user is null or length(v_password) < 16 then raise exception 'FAIL: admin_create_user returned no user / a weak password'; end if;

  select count(*) into v_count from public.profiles where id = v_user and tenant_id = '00000000-0000-0000-0000-0000000f0301' and role = 'site_manager';
  if v_count <> 1 then raise exception 'FAIL: profile not created in the caller''s tenant'; end if;

  select user_id, temporary_password into v_user, v_password from public.provision_employee_login('00000000-0000-0000-0000-0000000f0342', 'employee', '');
  select count(*) into v_count from public.employees where id = '00000000-0000-0000-0000-0000000f0342' and profile_id = v_user;
  if v_count <> 1 then raise exception 'FAIL: employee not linked to the provisioned login'; end if;
  raise notice 'PASS: admin_create_user and provision_employee_login work with pgcrypto in the extensions schema';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_ok boolean;
begin
  select bool_and(encrypted_password is not null and encrypted_password like '$2%') into v_ok
  from auth.users where email in ('created-h@example.com', 'provision-h@example.com');
  if not coalesce(v_ok, false) then raise exception 'FAIL: temporary passwords were not stored as bcrypt hashes'; end if;
  raise notice 'PASS: temporary passwords are stored as bcrypt hashes, never in clear';
end $$;

rollback;
