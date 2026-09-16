-- Sebetsa — P1 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, High finding: MFA for
-- platform_administrator/organization_administrator/hr_user was enforced
-- only as a dismissible UI banner — no RLS policy or RPC anywhere checked
-- the session's assurance level, so a compromised password for one of
-- these roles faced no MFA barrier at all).
--
-- Scope (documented explicitly, not a silent partial fix): this adds a
-- real, unbypassable (can't be dismissed, can't be skipped by calling the
-- RPC directly instead of using the UI) server-side gate on the two
-- highest-leverage privileged actions — provisioning a new user account
-- and changing a user's role — for the three MFA-required roles. It does
-- NOT hard-block every action those roles can take. Two reasons:
--
-- 1. mfaRequiredRoles.ts's own comment already documents that MFA
--    enrollment is not yet mandatory anywhere in the product — a blanket
--    hard block today, before enrollment exists for any real account,
--    would lock every current admin out of the entire application with
--    no path back in, which is a worse outcome than the gap being closed
--    here. User creation and role assignment are the two actions where a
--    stolen admin password does the most damage (privilege escalation,
--    new account provisioning) and are the correct place to start.
-- 2. Expanding this same public.mfa_step_up_required() check to more
--    RPCs/RLS policies once MFA enrollment is actually rolled out
--    org-wide is tracked as a P2 follow-up in
--    docs/SEBETSA_PRODUCTION_CHECKLIST.md — this migration establishes
--    the real, working mechanism (not a stub) that follow-up will reuse.
--
-- auth.jwt()->>'aal' is Supabase's own assurance-level claim (aal1 =
-- password only, aal2 = MFA-verified this session) — the same claim
-- src/features/mfa checks client-side, now also checked server-side.

create or replace function public.mfa_step_up_required()
returns boolean
language sql
stable
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
      ('platform_administrator', 'organization_administrator', 'hr_user')
    and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2'
$$;

comment on function public.mfa_step_up_required() is
  'True when the caller holds an MFA-required role (mfaRequiredRoles.ts) but the current session is not aal2 (MFA-verified). Gates admin_create_user/admin_update_user_role — see this migration''s header for why the scope stops there for now.';

create or replace function public.admin_create_user(
  p_email text,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_role public.user_role,
  p_tenant_id uuid default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_effective_tenant uuid;
  v_new_user_id uuid;
  v_temp_password text;
begin
  if public.mfa_step_up_required() then
    raise exception 'mfa_required: verify your authenticator app before creating a user';
  end if;

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
$$;

create or replace function public.admin_update_user_role(p_user_id uuid, p_new_role public.user_role)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target_tenant uuid;
  v_current_role public.user_role;
begin
  if public.mfa_step_up_required() then
    raise exception 'mfa_required: verify your authenticator app before changing a user''s role';
  end if;

  select tenant_id, role into v_target_tenant, v_current_role from public.profiles where id = p_user_id;

  if not found then
    raise exception 'not_found: no profile for user %', p_user_id;
  end if;

  if not public.can_manage_profiles(v_target_tenant) then
    raise exception 'insufficient_privilege: cannot manage this user''s tenant';
  end if;

  if not public.can_assign_role(p_new_role, v_current_role) then
    raise exception 'insufficient_privilege: cannot assign role %', p_new_role;
  end if;

  update auth.users set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', p_new_role) where id = p_user_id;

  perform set_config('app.allow_role_change', 'true', true);
  update public.profiles set role = p_new_role where id = p_user_id;

  perform public.write_audit_log(
    v_target_tenant, auth.uid(), 'role_changed', 'profiles', p_user_id,
    jsonb_build_object('role', v_current_role), jsonb_build_object('role', p_new_role)
  );
end;
$$;
