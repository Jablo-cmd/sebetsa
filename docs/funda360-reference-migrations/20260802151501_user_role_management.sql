-- Milestone 5 — User & Role Management
--
-- Architecture note: `profiles.tenant_id` (not `school_id`) and `profiles.id`
-- (the auth user id, not a separate `user_id`) already exist from Milestone
-- 3 and are used throughout the codebase (services, RLS, providers). This
-- migration reuses them rather than renaming — the columns this milestone's
-- brief calls `school_id`/`user_id` are the same concepts already in place.
--
-- `profiles.role` is new: a queryable MIRROR of the JWT `app_metadata.role`
-- claim, not a replacement for it. RLS and client-side authorization
-- (usePermissions, hasRole/hasPermission) continue to read the JWT claim
-- exclusively — that stays the single source of truth. This column exists
-- solely so the User Management directory can list/search/filter users by
-- role, which is otherwise impossible: a JWT only carries its own owner's
-- claims, so there is no way to read *other* users' roles without either
-- this denormalized column or an admin API call per row. It's kept in sync
-- with the JWT claim exclusively through admin_update_user_role() /
-- admin_create_user() below — never written directly by client code (see
-- the column-level grant near the end of this file).

create extension if not exists pgcrypto;

create type public.user_role as enum (
  'super_administrator', 'platform_administrator', 'support_engineer', 'school_owner',
  'principal', 'vice_principal', 'department_head', 'teacher', 'class_teacher', 'subject_teacher',
  'hr_manager', 'finance_manager', 'accountant', 'receptionist', 'admissions_officer', 'librarian',
  'transport_coordinator', 'sports_coordinator', 'medical_officer', 'parent', 'guardian', 'learner',
  'guest', 'auditor'
);

comment on type public.user_role is
  'Mirrors USER_ROLES in src/features/auth/types/auth.types.ts — keep both in sync.';

alter table public.profiles add column role public.user_role;

comment on column public.profiles.role is
  'Denormalized mirror of the JWT app_metadata.role claim — NOT the authorization source of truth (RLS and client permission checks read the JWT claim). Exists so the directory can list/filter by role. Written only by admin_update_user_role()/admin_create_user().';

create index profiles_role_idx on public.profiles (role);
create index profiles_tenant_id_role_idx on public.profiles (tenant_id, role);

-- ---------------------------------------------------------------------------
-- Write access: managers (school_owner/principal/hr_manager/platform admins —
-- the existing `profile.manage_any` set from ROLE_PERMISSIONS) can edit any
-- profile's contact info/status within their own tenant. Self-editing
-- (profiles_update_own, from Milestone 3) still applies alongside this.
create or replace function public.can_manage_profiles(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal', 'hr_manager')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_profiles(uuid) is
  'True for school_owner/principal/hr_manager of the target tenant, or any platform admin. Mirrors the app-level profile.manage_any permission.';

create policy profiles_update_by_manager
  on public.profiles
  for update
  to authenticated
  using (public.can_manage_profiles(tenant_id))
  with check (public.can_manage_profiles(tenant_id));

-- Column-level grant deliberately excludes `role` (and id/tenant_id/email/
-- created_at/updated_at) as self-documentation of intent, but Supabase
-- projects grant `authenticated` blanket table privileges by default (RLS,
-- not GRANT, is meant to be the real gate) — so this alone would NOT
-- actually stop a direct client UPDATE of `role` on a real project. The
-- trigger below is the real enforcement: it blocks any write to `role`
-- that isn't flagged as coming from admin_update_user_role().
grant update (first_name, last_name, phone, avatar_url, status) on public.profiles to authenticated;

-- Only a change flagged via this transaction-local setting (set by
-- admin_update_user_role() immediately before its UPDATE) may modify
-- `role`. This is what actually keeps the JWT claim and this mirror
-- column from drifting apart via a stray client-side write, independent
-- of whatever table-level grants a Supabase project has by default.
create or replace function public.prevent_direct_role_change()
returns trigger
language plpgsql
as $$
begin
  if new.role is distinct from old.role and coalesce(current_setting('app.allow_role_change', true), '') <> 'true' then
    raise exception 'insufficient_privilege: role can only be changed via admin_update_user_role()';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_direct_role_change
  before update on public.profiles
  for each row
  execute function public.prevent_direct_role_change();

-- A user (including a manager) may never change their OWN status — RLS
-- can't express "except your own row" within one USING/CHECK expression
-- cleanly across two different policies, so this is enforced as a trigger
-- instead, which sees both the old and new row.
create or replace function public.prevent_self_status_change()
returns trigger
language plpgsql
as $$
begin
  if new.id = auth.uid() and new.status is distinct from old.status and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot change your own account status';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_self_status_change
  before update on public.profiles
  for each row
  execute function public.prevent_self_status_change();

-- ---------------------------------------------------------------------------
-- Role assignment is narrower than general profile management (Milestone 5
-- brief §6): School Administrator (school_owner) may assign any of the
-- three school-level roles to school-level staff; Principal may only
-- promote/create Teachers; platform admins are unrestricted. Enforced here
-- (not just hidden in the UI) so a direct RPC call can't bypass it.
create or replace function public.can_assign_role(p_new_role public.user_role, p_target_current_role public.user_role)
returns boolean
language sql
stable
as $$
  select case
    when public.is_platform_admin() then true
    when coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'school_owner' then
      p_new_role in ('school_owner', 'principal', 'teacher')
      and (p_target_current_role is null or p_target_current_role in ('school_owner', 'principal', 'teacher'))
    when coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'principal' then
      p_new_role = 'teacher'
      and (p_target_current_role is null or p_target_current_role = 'teacher')
    else false
  end
$$;

grant execute on function public.can_manage_profiles(uuid) to authenticated;
grant execute on function public.can_assign_role(public.user_role, public.user_role) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_create_user: creates the auth.users + auth.identities rows a real
-- sign-in needs, plus the matching profile, in one SECURITY DEFINER call —
-- ordinary authenticated clients have no privilege to write auth.users
-- directly (nor should they). Returns a one-time temporary password for the
-- caller to relay to the new user; there is no transactional email sending
-- configured yet (see recommendations), so this is the interim mechanism.
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

comment on function public.admin_create_user(text, text, text, text, public.user_role, uuid) is
  'Privileged user provisioning (auth.users + auth.identities + profiles in one call). Returns a one-time temporary password — no email sending is configured yet.';

-- admin_update_user_role: the only way `profiles.role` and the JWT claim
-- are ever written, kept atomic so they can't drift apart.
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
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, public.user_role, uuid) to authenticated;
grant execute on function public.admin_update_user_role(uuid, public.user_role) to authenticated;