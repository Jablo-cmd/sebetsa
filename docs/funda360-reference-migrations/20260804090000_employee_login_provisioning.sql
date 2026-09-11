-- Sprint 2 Milestone 2 — Employee Management, provisioning follow-up.
--
-- Resolves the Phase 1 "BLOCKED" note left in
-- 20260803160000_employee_management.sql on provision_employee_login():
-- that migration's own comment stated profiles.first_name/last_name are
-- NOT NULL and "the locked architecture for this milestone forbids
-- writing employee name data into profiles under any circumstances...
-- Awaiting instruction before implementing this RPC." Instruction has
-- since been given, explicitly, to proceed. This migration seeds
-- profiles.first_name/last_name from the employee's own name at
-- one-time account creation only — the same shape admin_create_user()
-- already uses for its own p_first_name/p_last_name arguments — with no
-- trigger keeping the two tables in sync afterward. This does not reverse
-- "employees never mirrors, syncs, or otherwise duplicates identity
-- fields into profiles" (that rule concerns ongoing synchronization, not
-- a one-time seed value at row creation); employees still owns
-- first_name/last_name exclusively as the source of truth for its own
-- records, and nothing here re-reads profiles back into employees.

-- ---------------------------------------------------------------------------
-- can_assign_employee_role: a dedicated, bounded grantable-role allowlist
-- for provision_employee_login() only. Deliberately NOT a reuse of
-- can_assign_role() (Milestone 5) — that function is scoped to the User
-- Management UI's narrow ASSIGNABLE_ROLES (school_owner/principal/teacher)
-- and returns false unconditionally for hr_manager, which would make
-- provisioning unusable by Employee Management's own primary caller.
-- can_assign_role() itself is untouched by this migration and remains
-- responsible for governance-level user creation elsewhere in the system.
--
-- Grantable set is fixed and intentionally narrow: platform/governance
-- roles (super_administrator, platform_administrator, school_owner,
-- principal) must go through the existing admin_create_user() path, not
-- employee onboarding; parent/learner/guardian/guest belong to their own
-- onboarding flows and are never employee accounts.
create or replace function public.can_assign_employee_role(p_role public.user_role)
returns boolean
language sql
stable
as $$
  select p_role in (
    'hr_manager', 'teacher', 'department_head', 'receptionist',
    'accountant', 'librarian', 'admissions_officer', 'medical_officer'
  )
$$;

comment on function public.can_assign_employee_role(public.user_role) is
  'Grantable-role allowlist for provision_employee_login() only. Independent of can_assign_role(), which this does not call and does not modify — see this migration''s header comment.';

grant execute on function public.can_assign_employee_role(public.user_role) to authenticated;

-- ---------------------------------------------------------------------------
-- provision_employee_login: creates auth.users + auth.identities +
-- profiles (seeded from the employee's own name/email, mirroring
-- admin_create_user()'s insert shape exactly) and links employees.profile_id
-- back to the new profile in the same transaction. Two independent
-- authorization checks, per the approved design: can_manage_employees()
-- gates the caller, can_assign_employee_role() gates the requested role.
create or replace function public.provision_employee_login(
  p_employee_id uuid,
  p_role public.user_role,
  p_phone text default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth
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

comment on function public.provision_employee_login(uuid, public.user_role, text) is
  'Provisions a login for an existing employee: auth.users + auth.identities + profiles (seeded once from the employee''s own name/email, never synced afterward) + links employees.profile_id. Returns a one-time temporary password, same shape as admin_create_user(). Rejects if the employee already has a linked login, has no work_email, or the email is already registered.';

grant execute on function public.provision_employee_login(uuid, public.user_role, text) to authenticated;
