-- Learner Portal domain (1/1) — a role-scoped, read-only self-service
-- experience for a learner logging in as themselves.
--
-- Mirrors the Parent Portal exactly: no new identity table, no new auth
-- flow, no duplicated relationship. `learners.profile_id` already exists
-- (ON DELETE SET NULL), the `learner` role is already in user_role, and
-- is_learner_self(learner_id) (learners.profile_id = auth.uid()) was added
-- in the Homework domain. This migration adds:
--
--   1. provision_learner_login(learner, email, phone?) — the same
--      auth.users + auth.identities + profiles + link shape as
--      provision_employee_login(); returns a one-time temporary password
--      for staff to hand over. Gated by can_manage_learners().
--
--   2. SELECT-only RLS for the learner, one new additive policy per table,
--      the exact pattern parent_portal_v1 established — reference data via
--      can_view_academic_reference_as_learner() (tenant + role), personal
--      data via is_learner_self(learner_id). Homework
--      (assignment_submissions / assignments) and Report Cards
--      (report_cards_select_learner) already carry is_learner_self /
--      profile_id = auth.uid() clauses from their own domains — untouched.
--
--   3. announcements: the `all_staff` audience test was
--      `role not in ('parent','guardian')`, which a `learner` role would
--      wrongly match. Re-declared here to also exclude 'learner', and the
--      fan-out link_path now routes a learner recipient to
--      /learner/announcements.
--
-- NO admin surface, NO write capability anywhere. Behaviour and medical
-- are deliberately NOT exposed to the learner (same reasoning
-- parent_portal_v1 documents for guardians — no per-row visibility tier).

-- ===========================================================================
-- 1. provision_learner_login
-- ===========================================================================

create or replace function public.provision_learner_login(
  p_learner_id uuid,
  p_email text,
  p_phone text default null
) returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school_id uuid;
  v_first_name text;
  v_last_name text;
  v_existing_profile_id uuid;
  v_new_user_id uuid;
  v_temp_password text;
  v_email text := lower(trim(p_email));
begin
  select school_id, first_name, last_name, profile_id
    into v_school_id, v_first_name, v_last_name, v_existing_profile_id
    from public.learners where id = p_learner_id;

  if not found then raise exception 'not_found: no learner %', p_learner_id; end if;
  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage learners for this school';
  end if;
  if v_existing_profile_id is not null then
    raise exception 'already_provisioned: learner % already has a linked login', p_learner_id;
  end if;
  if v_email is null or v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid_argument: a valid email address is required';
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
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
      'role', 'learner', 'tenant_id', v_school_id
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
  values (v_new_user_id, v_school_id, v_first_name, v_last_name, v_email, p_phone, 'learner', 'active');

  update public.learners set profile_id = v_new_user_id where id = p_learner_id;

  perform public.write_audit_log(v_school_id, auth.uid(), 'learner_login_provisioned', 'learners', p_learner_id, null,
    jsonb_build_object('profile_id', v_new_user_id, 'email', v_email));

  return query select v_new_user_id, v_temp_password;
end;
$$;

comment on function public.provision_learner_login(uuid, text, text) is
  'Provisions a login for an existing learner: auth.users + auth.identities + profiles (role=learner) + links learners.profile_id. Returns a one-time temporary password, same shape as provision_employee_login(). Rejects if the learner already has a linked login or the email is already registered. Gated by can_manage_learners().';

revoke execute on function public.provision_learner_login(uuid, text, text) from public;
grant execute on function public.provision_learner_login(uuid, text, text) to authenticated;

-- ===========================================================================
-- 2. Reference-data learner visibility
-- ===========================================================================

create or replace function public.can_view_academic_reference_as_learner(target_school_id uuid)
returns boolean language sql stable as $$
  select target_school_id = public.current_tenant_id()
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'learner'
$$;
comment on function public.can_view_academic_reference_as_learner(uuid) is
  'A learner may read non-sensitive academic catalogue/label data (grade / class / subject names, class-teacher assignments, timetable) tenant-wide — not personal information about any specific learner. Mirrors can_view_academic_reference_as_guardian().';
grant execute on function public.can_view_academic_reference_as_learner(uuid) to authenticated;

create policy grades_select_for_learners on public.grades
  for select to authenticated using (public.can_view_academic_reference_as_learner(school_id));
create policy classes_select_for_learners on public.classes
  for select to authenticated using (public.can_view_academic_reference_as_learner(school_id));
create policy subjects_select_for_learners on public.subjects
  for select to authenticated using (public.can_view_academic_reference_as_learner(school_id));
create policy class_teacher_assignments_select_for_learners on public.class_teacher_assignments
  for select to authenticated using (public.can_view_academic_reference_as_learner(school_id));
create policy timetable_entries_select_for_learners on public.timetable_entries
  for select to authenticated using (public.can_view_academic_reference_as_learner(school_id));

-- ===========================================================================
-- 3. Learner-specific self visibility — is_learner_self(learner_id) scoping
-- ===========================================================================

create policy learner_enrollments_select_for_self on public.learner_enrollments
  for select to authenticated using (public.is_learner_self(learner_id));

create policy attendance_records_select_for_self on public.attendance_records
  for select to authenticated using (public.is_learner_self(learner_id));

create policy assessment_results_select_for_self on public.assessment_results
  for select to authenticated using (public.is_learner_self(learner_id));

-- assessments has no learner_id: visible if the learner has a result on it.
create policy assessments_select_for_self on public.assessments
  for select to authenticated using (
    exists (
      select 1 from public.assessment_results ar
      where ar.assessment_id = assessments.id and public.is_learner_self(ar.learner_id)
    )
  );

create policy learner_documents_select_for_self on public.learner_documents
  for select to authenticated using (public.is_learner_self(learner_id));

create policy learner_documents_storage_select_for_learners
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'learner-documents'
    and public.is_learner_self(((storage.foldername(name))[2])::uuid)
  );

-- ===========================================================================
-- 4. announcements — stop a `learner` role matching the `all_staff` audience,
--    and route a learner recipient's link_path to /learner/announcements.
--    Re-declared with the exact prior bodies + the 'learner' exclusion.
-- ===========================================================================

drop policy announcements_select on public.announcements;
create policy announcements_select on public.announcements
  for select to authenticated using (
    (
      school_id = public.current_tenant_id()
      and (
        public.can_manage_school(school_id)
        or audience = 'everyone'
        or (audience = 'all_guardians' and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('parent', 'guardian'))
        or (audience = 'all_staff' and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('parent', 'guardian', 'learner'))
      )
    )
    or public.is_platform_admin()
  );

create or replace function public.announcements_notify_recipients()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
  v_link_path text;
begin
  for v_recipient in
    select id, role from public.profiles
    where tenant_id = new.school_id
      and status = 'active'
      and id is distinct from new.created_by
      and (
        new.audience = 'everyone'
        or (new.audience = 'all_guardians' and role in ('parent', 'guardian'))
        or (new.audience = 'all_staff' and role not in ('parent', 'guardian', 'learner'))
      )
  loop
    v_link_path := case
      when v_recipient.role in ('parent', 'guardian') then '/parent/announcements'
      when v_recipient.role = 'learner' then '/learner/announcements'
      else '/announcements'
    end;
    perform public.create_notification(
      v_recipient.id, 'announcement', new.title, new.body, new.school_id, 'announcements', new.id, v_link_path
    );
  end loop;

  return new;
end;
$$;
