-- Server-side multi-factor enforcement.
--
-- Until now MFA was a client-side nag: a stolen administrator password was
-- enough to reach every privileged operation, because no database rule looked
-- at the session's assurance level. Every tenant policy and every permission
-- helper (can_manage_operations, can_manage_employees, can_manage_profiles,
-- can_manage_org_structure, can_approve_leave, can_access_site, the scope and
-- audit policies, …) resolves its caller through current_tenant_id() or
-- is_platform_admin(). Both now fail closed unless mfa_satisfied(), so there is
-- one choke point and no RPC or direct table call can bypass it.
--
-- A session must be at assurance level aal2 (the `aal` claim of the Supabase
-- JWT, set only after a TOTP challenge is verified) when EITHER
--   * the caller's role is privileged (mfa_roles()), OR
--   * the caller has a verified MFA factor (anyone who enrolled gets the
--     protection they asked for; a session that skips the challenge is refused).
--
-- Enrolment still works for a privileged user who has not enrolled yet: it is
-- a GoTrue Auth API operation, not a database one, and a session that has
-- verified a factor becomes aal2. At aal1 such a user can read only their own
-- profile row (the app needs it to route them to enrolment) and their own
-- notifications; everything tenant-scoped is empty or refused.
--
-- Break-glass: security_settings.mfa_enforced can be turned off by whoever has
-- direct database / service-role access (never by an application user — the
-- table has no policy and no grants for anon/authenticated). Administrative
-- recovery of a lost authenticator is `auth.admin.mfa.deleteFactor` followed by
-- re-enrolment; see docs/MFA.md.

create table if not exists public.security_settings (
  key         text primary key,
  bool_value  boolean not null,
  updated_at  timestamptz not null default now()
);

alter table public.security_settings enable row level security;
alter table public.security_settings force row level security;
revoke all on public.security_settings from anon, authenticated;

insert into public.security_settings (key, bool_value) values ('mfa_enforced', true)
on conflict (key) do nothing;

comment on table public.security_settings is
  'Operator-controlled platform security switches. No policy and no client grants: readable only through definer helpers, writable only with direct database / service-role access.';

create or replace function public.mfa_roles()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array['platform_administrator', 'organization_administrator', 'operations_manager', 'hr_user']::text[]
$$;

create or replace function public.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select case
    when coalesce(auth.jwt() ->> 'aal', '') = 'aal2' then true
    when auth.uid() is null then true
    when not coalesce((select s.bool_value from public.security_settings s where s.key = 'mfa_enforced'), true) then true
    when coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = any (public.mfa_roles()) then false
    when exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified') then false
    else true
  end
$$;

revoke execute on function public.mfa_satisfied() from public, anon;
revoke execute on function public.mfa_roles() from public, anon;
grant execute on function public.mfa_satisfied() to authenticated;
grant execute on function public.mfa_roles() to authenticated;

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles
   where id = auth.uid() and status = 'active' and public.mfa_satisfied()
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'platform_administrator'
    and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.status <> 'active')
    and public.mfa_satisfied()
$$;

-- ---------------------------------------------------------------------------
-- Fail-closed permission helpers.
--
-- The boolean helpers were written as `target = current_tenant_id() and role in
-- (…) or is_platform_admin()`. When current_tenant_id() is NULL (no active
-- profile, or — now — MFA not satisfied) that expression is NULL, not false,
-- and an RPC written `if not can_manage_x(t) then raise …` does NOT raise on
-- NULL: it silently proceeds. Policies treat NULL as deny, which hid the
-- problem, but SECURITY DEFINER RPCs do not. Wrap every such helper so it can
-- only ever return true or false.
do $$
declare
  r record;
  v_def text;
  v_src text;
  v_body text;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('can_access_site', 'can_approve_leave', 'can_assign_role', 'can_manage_employees',
                         'can_manage_leave', 'can_manage_operations', 'can_manage_org_structure',
                         'can_manage_profiles', 'can_view_leave_broad', 'is_own_employee')
  loop
    select pg_get_functiondef(r.oid), prosrc into v_def, v_src from pg_proc where oid = r.oid;
    continue when v_src like '%coalesce((%), false)%';
    v_body := regexp_replace(btrim(v_src, E' \n\t'), ';\s*$', '');
    v_def := replace(v_def, v_src, E'\n  select coalesce((' || v_body || E'), false)\n');
    execute v_def;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- hr_user carve-out on employees/departments/positions.
--
-- The original policies allowed `role = 'hr_user'` with no tenant predicate and
-- no MFA check: an hr_user could read and write these tables in ANY tenant, and
-- at aal1. Bind the carve-out to the caller's own tenant through
-- current_tenant_id(), which is MFA-aware.
do $$
declare t text;
begin
  foreach t in array array['employees', 'departments', 'positions'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write_by_manager', t);
    execute format($p$create policy %I on public.%I for all to authenticated
      using (public.can_manage_org_structure(tenant_id)
             or (tenant_id = public.current_tenant_id() and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user'))
      with check (public.can_manage_org_structure(tenant_id)
             or (tenant_id = public.current_tenant_id() and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user'))$p$,
      t || '_write_by_manager', t);
  end loop;
end $$;
