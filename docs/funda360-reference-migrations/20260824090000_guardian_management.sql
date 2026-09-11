-- Guardian / Parent Management
--
-- Phase 1 audit finding: guardians are already modelled correctly. There is
-- no separate "person" or "guardian" entity to invent — a guardian IS an
-- existing `profiles` row (role='parent'/'guardian'), and `learner_guardians`
-- is already a pure many-to-many join table between learners and profiles
-- (unique on (learner_id, guardian_profile_id), no uniqueness constraint on
-- either column alone). One guardian with many learners, and one learner
-- with many guardians, both already work today with zero schema change —
-- see 20260803190000_learner_management.sql. This migration only fills two
-- concrete, verified gaps found during that audit:
--
--   1. The relationship itself has no way to record "emergency contact" or
--      "authorised pickup" status (Product Phase 2 requirement) — only
--      relationship_type and is_primary exist. Purely additive columns on
--      the existing table, same pattern as is_primary itself.
--
--   2. There is no way to CREATE a brand-new guardian at all.
--      GuardianFormModal (see LearnerGuardiansSection) only searches
--      EXISTING profiles — and admin_create_user()'s can_assign_role() gate
--      (20260802151501_user_role_management.sql) only ever permits creating
--      school_owner/principal/teacher, never parent/guardian. A school with
--      a genuinely new parent has had no path to add them. This adds
--      admin_create_guardian(), mirroring admin_create_user()'s mechanics
--      exactly, but gated by can_manage_learners() — the same permission
--      already governing learner_guardians writes — rather than the staff
--      role-assignment ladder, which is a different concern (career-grade
--      staff hierarchy) that guardians were never part of.
--
-- Guardian identity (name/phone/email) stays on `profiles`, reusing the
-- existing reusable person entity exactly as instructed. Two additional,
-- guardian-only fields (address, an identification/reference number) are
-- NOT added to `profiles` — that would leak guardian-only columns onto
-- every one of the other 23 roles sharing that table, and column-level
-- profile edits are gated by can_manage_profiles() (school_owner/principal/
-- hr_manager), which deliberately excludes admissions_officer — the role
-- most likely to actually be entering this data. Instead, a small 1:1
-- extension table gated by can_view_learners()/can_manage_learners()
-- mirrors the established learner_medical_information precedent exactly:
-- a narrow, separately-RLS-gated extension of an existing entity, not a
-- new competing concept.

-- ---------------------------------------------------------------------------
-- 1. Relationship metadata

alter table public.learner_guardians add column is_emergency_contact boolean not null default false;
alter table public.learner_guardians add column is_authorized_pickup boolean not null default false;

comment on column public.learner_guardians.is_emergency_contact is 'Whether this guardian should be treated as an emergency contact for this learner. Independent of learner_emergency_contacts, which is for non-guardian contacts with no login/account.';
comment on column public.learner_guardians.is_authorized_pickup is 'Whether this guardian is authorised to collect/pick up this learner.';

-- ---------------------------------------------------------------------------
-- 2. guardian_profile_details — 1:1 extension of profiles for guardian-only
-- fields, exactly mirroring learner_medical_information's shape (separate
-- table, separate RLS, never added to the shared parent table).

create table public.guardian_profile_details (
  id                   uuid primary key default gen_random_uuid(),
  school_id            uuid not null references public.schools (id) on delete cascade,
  guardian_profile_id  uuid not null unique references public.profiles (id) on delete cascade,
  address              text,
  id_number            text,
  created_by           uuid references public.profiles (id) on delete set null,
  updated_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.guardian_profile_details is 'Guardian-only identity fields (address, identification/reference number) kept off the shared profiles table on purpose — see migration header. One row per guardian profile, created on first use, not necessarily at profile-creation time.';
comment on column public.guardian_profile_details.id_number is 'Free-text identification/reference number — deliberately not validated to a specific national ID format, same treatment as learners.id_number.';

create index guardian_profile_details_school_id_idx on public.guardian_profile_details (school_id);

create trigger guardian_profile_details_set_updated_at
  before update on public.guardian_profile_details
  for each row
  execute function public.set_updated_at();

create trigger guardian_profile_details_set_created_updated_by
  before insert or update on public.guardian_profile_details
  for each row
  execute function public.set_created_updated_by();

create or replace function public.guardian_profile_details_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guardian_tenant_id uuid;
begin
  select tenant_id into v_guardian_tenant_id from public.profiles where id = new.guardian_profile_id;
  if v_guardian_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: guardian_profile_id must belong to the same school';
  end if;
  return new;
end;
$$;

comment on function public.guardian_profile_details_validate_tenant() is
  'SECURITY DEFINER for the same reason every other *_validate_tenant() trigger on a table referencing profiles is (see learner_guardians_validate_tenant): a caller with can_manage_learners() but no general profile read access must still be able to insert this row.';

create trigger guardian_profile_details_validate_tenant_trigger
  before insert or update on public.guardian_profile_details
  for each row
  execute function public.guardian_profile_details_validate_tenant();

alter table public.guardian_profile_details enable row level security;
alter table public.guardian_profile_details force row level security;

-- Reuses can_view_learners()/can_manage_learners() rather than inventing a
-- new can_view_guardians()/can_manage_guardians() pair — the actor set that
-- should manage guardian relationships (school_owner, principal,
-- admissions_officer, platform admins) is exactly the actor set that
-- already manages learners; no separate security model is warranted.
create policy guardian_profile_details_select on public.guardian_profile_details
  for select to authenticated using (public.can_view_learners(school_id));
create policy guardian_profile_details_insert on public.guardian_profile_details
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy guardian_profile_details_update on public.guardian_profile_details
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible for any authenticated caller, same as every other table in
-- this schema. There is nothing to archive here (unlike learner_guardians,
-- this row has no independent lifecycle — it simply stops being read once
-- every learner_guardians link for the guardian is archived).

-- ---------------------------------------------------------------------------
-- 3. admin_create_guardian — mirrors admin_create_user()'s auth.users +
-- auth.identities + profiles mechanics exactly, but gated by
-- can_manage_learners() instead of can_assign_role()/can_manage_profiles():
-- guardian creation is a learner-management action, not a staff
-- role-assignment action, and admissions_officer (who holds
-- can_manage_learners() but NOT can_assign_role() for any role, and NOT
-- can_manage_profiles()) is exactly the role most likely to use this.
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

comment on function public.admin_create_guardian(text, text, text, text, uuid, text, text) is
  'Privileged guardian provisioning (auth.users + auth.identities + profiles, role=guardian, in one call), gated by can_manage_learners() rather than the staff role-assignment ladder. Returns a one-time temporary password, same interim mechanism as admin_create_user() — no transactional email sending is configured yet. Existing role=parent profiles created before this function existed remain valid guardians; this function only ever creates role=guardian going forward.';

grant execute on function public.admin_create_guardian(text, text, text, text, uuid, text, text) to authenticated;
