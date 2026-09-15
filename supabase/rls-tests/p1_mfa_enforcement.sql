-- Sebetsa — regression coverage for the P1 MFA server-side enforcement
-- (docs/PRODUCTION_READINESS_AUDIT.md, fixed in
-- 20260919090600_p1_mfa_server_side_enforcement.sql).
--
-- Confirmed by running this file against the pre-fix migration set: the
-- SECURITY_FAILURE-labelled assertion below reproducibly failed (an
-- organization_administrator without aal2 could create a user) before the
-- fix, and passes after it.
--
--   supabase start
--   cat supabase/rls-tests/p1_mfa_enforcement.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000091', 'Org H (MFA enforcement)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000092', 'authenticated', 'authenticated', 'admin-h@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000093', 'authenticated', 'authenticated', 'sitemgr-h@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', 'Admin', 'H', 'admin-h@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000091', 'Site', 'MgrH', 'sitemgr-h@example.com', 'site_manager', 'active');

-- MFA-required role (organization_administrator), session at aal1 (no
-- "aal" claim at all — the common case for an account that hasn't stepped
-- up this session, which is also what an attacker with just the stolen
-- password would present). admin_create_user must be blocked.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000092","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.admin_create_user('new-user@example.com', 'New', 'User', null, 'employee', null);
    raise exception 'SECURITY_FAILURE: organization_administrator without aal2 created a user';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: organization_administrator without aal2 (MFA step-up) cannot create a user (%)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    perform public.admin_update_user_role('00000000-0000-0000-0000-000000000093', 'hr_user');
    raise exception 'SECURITY_FAILURE: organization_administrator without aal2 changed a user''s role';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: organization_administrator without aal2 cannot change a user''s role (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- Same caller, but with an aal2 (MFA step-up completed) session — both
-- calls must now succeed (control: proves the gate is aal-specific, not a
-- blanket new denial).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000092","app_metadata":{"role":"organization_administrator"},"aal":"aal2"}';

do $$
declare v_new_user_id uuid;
begin
  select user_id into v_new_user_id from public.admin_create_user('new-user-2@example.com', 'New', 'User2', null, 'employee', null);
  if v_new_user_id is null then raise exception 'FAIL: organization_administrator with aal2 could not create a user'; end if;
  raise notice 'PASS: organization_administrator with aal2 can create a user';
end $$;

do $$
begin
  perform public.admin_update_user_role('00000000-0000-0000-0000-000000000093', 'hr_user');
  raise notice 'PASS: organization_administrator with aal2 can change a user''s role';
end $$;

reset role;
reset request.jwt.claims;

-- A role NOT in the MFA-required set (site_manager) is unaffected by this
-- gate either way — mfa_step_up_required() must be false for it regardless
-- of aal, since it was never one of the three MFA-required roles.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000093","app_metadata":{"role":"site_manager"}}';

do $$
begin
  if public.mfa_step_up_required() is not false then
    raise exception 'FAIL: mfa_step_up_required() should be false for site_manager (not an MFA-required role)';
  end if;
  raise notice 'PASS: site_manager (not an MFA-required role) is unaffected by the gate';
end $$;

reset role;
reset request.jwt.claims;

rollback;
