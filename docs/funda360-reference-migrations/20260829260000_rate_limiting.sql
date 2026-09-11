-- FND-SEC-011: Application-level rate limiting beyond Supabase's own
-- defaults.
--
-- SCOPE: this platform has no custom backend layer (no Edge Functions,
-- no API gateway) — every write goes straight through PostgREST or a
-- SECURITY DEFINER RPC, so genuine (not just client-side, trivially
-- bypassed) rate limiting has to live in Postgres itself. Supabase's own
-- GoTrue service already rate-limits login/signup/password-reset attempts
-- at the platform level — this migration does not duplicate that. It
-- targets the highest-risk gap that IS this app's own responsibility: the
-- three privileged account-provisioning RPCs (admin_create_user,
-- admin_create_guardian, provision_employee_login), which each mint a new
-- real auth.users row. A single compromised or malicious privileged
-- account (school_owner/principal/hr_manager) could otherwise script
-- hundreds of fake accounts in seconds — nothing before this migration
-- stopped that.
--
-- All three share ONE budget (action_key = 'account_provisioning'),
-- keyed per actor (auth.uid()) — spreading calls across the three
-- different RPCs must not let an actor multiply their effective limit.
-- 20 provisioning calls per rolling hour per actor is a reasonable
-- engineering default (generous enough for legitimate bulk onboarding at
-- the start of a term, tight enough to blunt a scripted abuse attempt) —
-- not a security-audited figure, and deliberately passed as a parameter
-- to check_rate_limit() rather than hardcoded, so it can be tuned without
-- a schema change if real usage patterns say otherwise.
--
-- rate_limit_events has no RLS policy of any kind (beyond FORCE ROW LEVEL
-- SECURITY itself) — same posture as audit_log's own write path: reachable
-- only from inside another SECURITY DEFINER function's body, never
-- directly by `authenticated`.

create table public.rate_limit_events (
  id                 uuid primary key default gen_random_uuid(),
  actor_profile_id   uuid not null,
  action_key         text not null,
  occurred_at        timestamptz not null default now()
);

comment on table public.rate_limit_events is 'A rolling-window event log powering check_rate_limit() — not a general audit trail (see audit_log for that), just enough history to count "how many times has this actor done this action recently". No RLS policy exists for authenticated; only reachable via check_rate_limit()''s own SECURITY DEFINER body.';

create index rate_limit_events_actor_action_idx on public.rate_limit_events (actor_profile_id, action_key, occurred_at);

alter table public.rate_limit_events enable row level security;
alter table public.rate_limit_events force row level security;

-- No periodic cleanup job exists yet for old rows here — this table will
-- grow unboundedly over time. Left as a known, documented gap (same
-- category as the rest of this schema's retention posture — see
-- FND-SEC-008) rather than silently assumed solved; a pg_cron job
-- deleting rows older than, say, 7 days would be a small, low-risk
-- follow-up once FND-SEC-008's actual retention policy is decided.

create or replace function public.check_rate_limit(
  p_action_key text,
  p_max_count  integer,
  p_window     interval
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent_count integer;
begin
  select count(*) into v_recent_count
    from public.rate_limit_events
    where actor_profile_id = auth.uid()
      and action_key = p_action_key
      and occurred_at > now() - p_window;

  if v_recent_count >= p_max_count then
    raise exception 'rate_limited: too many "%" actions (max % per %) — please try again later', p_action_key, p_max_count, p_window;
  end if;

  insert into public.rate_limit_events (actor_profile_id, action_key) values (auth.uid(), p_action_key);
end;
$$;

comment on function public.check_rate_limit(text, integer, interval) is
  'Raises rate_limited: ... once the caller has performed p_action_key more than p_max_count times within the trailing p_window; otherwise records this attempt and returns. Meant to be reachable only from inside another SECURITY DEFINER function''s own body — explicitly revoked from PUBLIC below, since a plain `create function` in this project grants EXECUTE to the PUBLIC pseudo-role by default (confirmed directly via pg_proc.proacl showing a leading `=X/postgres` entry — the same PUBLIC-grant mechanism 20260822010000_function_execute_privilege_correction.sql already documented and corrected for the functions that existed at that time; revoking from authenticated alone is insufficient, since every role inherits a PUBLIC grant regardless of a role-specific revoke — confirmed the hard way while verifying this exact migration).';

-- Explicitly revoke from PUBLIC (not just authenticated) — see the
-- comment above. A direct call is not itself a privilege-escalation risk
-- (it only records an entry against the caller's own auth.uid()), but the
-- intended trust boundary is "internal helper", not "public API", so it
-- is revoked to actually match that intent rather than merely documenting
-- a gap between intent and the real ACL.
revoke execute on function public.check_rate_limit(text, integer, interval) from public;

-- ---------------------------------------------------------------------------
-- admin_create_user / admin_create_guardian / provision_employee_login —
-- redefined (create or replace, not editing their original migration
-- files) to call check_rate_limit() first. Every other line of each
-- function body is unchanged from its original definition, EXCEPT the
-- search_path, which now also includes `extensions` — see the fix note
-- below.
--
-- PRE-EXISTING BUG FIXED IN PASSING: all three functions' original
-- search_path was `public, auth`, which does not include `extensions`,
-- the schema pgcrypto actually lives in on this Supabase instance
-- (confirmed via pg_extension/pg_proc: gen_random_bytes and crypt/
-- gen_salt all resolve to `extensions`, not `public`). A normal
-- connection's default search_path ("$user", public, extensions) would
-- have found them, which is why this was never caught by mocked e2e
-- tests (they never execute the real function body) nor by the RLS test
-- harness (its disposable postgres:16-alpine container installs pgcrypto
-- into `public` by default, masking the gap) — only a real, live smoke
-- test against the actual local Supabase instance surfaced it, as
-- `function gen_random_bytes(integer) does not exist`. Not introduced by
-- this migration's rate-limiting work — copied verbatim from each
-- function's original definition — but fixed here since these three
-- bodies are already being redefined in this file.

-- Was: 20260802151501_user_role_management.sql
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
set search_path = public, auth, extensions
as $$
declare
  v_effective_tenant uuid;
  v_new_user_id uuid;
  v_temp_password text;
begin
  perform public.check_rate_limit('account_provisioning', 20, interval '1 hour');

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

-- Was: 20260824090000_guardian_management.sql
create or replace function public.admin_create_guardian(
  p_email text,
  p_first_name text,
  p_last_name text,
  p_phone text default null,
  p_tenant_id uuid default null,
  p_address text default null,
  p_id_number text default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_effective_tenant uuid;
  v_new_user_id uuid;
  v_temp_password text;
begin
  perform public.check_rate_limit('account_provisioning', 20, interval '1 hour');

  if public.is_platform_admin() then
    v_effective_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  else
    v_effective_tenant := public.current_tenant_id();
  end if;

  if not public.can_manage_learners(v_effective_tenant) then
    raise exception 'insufficient_privilege: cannot create a guardian for this school';
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
      'role', 'guardian', 'tenant_id', v_effective_tenant
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
  values (v_new_user_id, v_effective_tenant, p_first_name, p_last_name, p_email, p_phone, 'guardian', 'active');

  if p_address is not null or p_id_number is not null then
    insert into public.guardian_profile_details (school_id, guardian_profile_id, address, id_number)
    values (v_effective_tenant, v_new_user_id, p_address, p_id_number);
  end if;

  return query select v_new_user_id, v_temp_password;
end;
$$;

-- Was: 20260804090000_employee_login_provisioning.sql
create or replace function public.provision_employee_login(
  p_employee_id uuid,
  p_role public.user_role,
  p_phone text default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_school_id uuid;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_existing_profile_id uuid;
  v_new_user_id uuid;
  v_temp_password text;
begin
  perform public.check_rate_limit('account_provisioning', 20, interval '1 hour');

  select school_id, first_name, last_name, work_email, profile_id
    into v_school_id, v_first_name, v_last_name, v_email, v_existing_profile_id
    from public.employees
    where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this school';
  end if;

  if not public.can_assign_employee_role(p_role) then
    raise exception 'insufficient_privilege: cannot provision a login with role %', p_role;
  end if;

  if v_existing_profile_id is not null then
    raise exception 'already_provisioned: employee % already has a linked login', p_employee_id;
  end if;

  if v_email is null then
    raise exception 'missing_email: employee has no work email to provision a login with';
  end if;

  if exists (select 1 from auth.users u where u.email = v_email) then
    raise exception 'email_taken: % is already registered', v_email;
  end if;

  v_new_user_id := gen_random_uuid();
  v_temp_password := encode(gen_random_bytes(18), 'base64');

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_new_user_id, 'authenticated', 'authenticated', v_email,
    crypt(v_temp_password, gen_salt('bf')), now(),
    jsonb_build_object(
      'provider', 'email', 'providers', jsonb_build_array('email'),
      'role', p_role, 'tenant_id', v_school_id
    ),
    jsonb_build_object('first_name', v_first_name, 'last_name', v_last_name),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_new_user_id,
    jsonb_build_object('sub', v_new_user_id::text, 'email', v_email),
    'email', v_new_user_id::text, now(), now(), now()
  );

  insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status)
  values (v_new_user_id, v_school_id, v_first_name, v_last_name, v_email, p_phone, p_role, 'active');

  update public.employees set profile_id = v_new_user_id where id = p_employee_id;

  return query select v_new_user_id, v_temp_password;
end;
$$;
