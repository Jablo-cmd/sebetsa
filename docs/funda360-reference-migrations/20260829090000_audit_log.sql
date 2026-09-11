-- Audit Log Foundation (FND-ARCH-001)
--
-- No queryable cross-domain audit trail existed before this migration —
-- every table already has created_by/updated_by (who/when for THAT row),
-- but nothing could answer "show me every sensitive action in the last 30
-- days" across role changes, employee termination, learner status changes,
-- and finance.
--
-- Deliberately NOT a blanket trigger on every table — that would be noisy
-- (every minor edit to every row logged) and slower for low-value writes.
-- Two insertion points instead:
--   1. `write_audit_log()` called explicitly from inside the handful of
--      existing SECURITY DEFINER RPCs that already centralize genuinely
--      privileged actions (role changes, employee lifecycle, learner
--      status/promotion) — re-declared here via `create or replace
--      function` with their exact prior bodies plus one added audit call,
--      not edited in their original migration files.
--   2. A narrow, explicit trigger on the two Finance tables added this
--      session that have no RPC front door at all (learner_fee_refunds,
--      learner_fee_adjustments — both are plain RLS-gated table writes,
--      not RPC-mediated) — attached to exactly these two tables by name,
--      not generically to "every table", so this is still a deliberate
--      allowlist, not the blanket-trigger approach the brief warns against.
--
-- Writes bypass RLS entirely (SECURITY DEFINER functions running as table
-- owner) — the same mechanism admin_create_user already uses to write
-- auth.users directly. There is no INSERT/UPDATE/DELETE policy for
-- `authenticated` on audit_log at all: a compromised or malicious client
-- session can never forge, edit, or erase an audit row, only the
-- functions/triggers below can ever write one.

create table public.audit_log (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools (id) on delete cascade,
  actor_profile_id   uuid references public.profiles (id) on delete set null,
  action             text not null check (char_length(action) > 0),
  entity_table       text not null check (char_length(entity_table) > 0),
  entity_id          uuid not null,
  before             jsonb,
  after              jsonb,
  created_at         timestamptz not null default now()
);

comment on table public.audit_log is 'Append-only audit trail for sensitive/privileged actions. school_id is NULL for platform-level actions (e.g. a super_administrator role change with no tenant). No UPDATE/DELETE policy anywhere, and no INSERT policy for `authenticated` — every row is written by a SECURITY DEFINER function or trigger, bypassing RLS, so a client can never forge or tamper with the trail.';
comment on column public.audit_log.action is 'A short, stable machine-readable label (e.g. "role_changed", "employee_terminated") — not a free-text description.';
comment on column public.audit_log.before is 'The entity''s prior state (jsonb), where meaningful — null for a creation event.';
comment on column public.audit_log.after is 'The entity''s new state (jsonb) — null for a pure deletion event (none currently exist; this schema never hard-deletes).';

create index audit_log_school_id_idx on public.audit_log (school_id);
create index audit_log_entity_idx on public.audit_log (entity_table, entity_id);
create index audit_log_actor_idx on public.audit_log (actor_profile_id);
create index audit_log_created_at_idx on public.audit_log (created_at);

-- ---------------------------------------------------------------------------
-- write_audit_log — the explicit-call insertion point for RPCs.

create or replace function public.write_audit_log(
  p_school_id        uuid,
  p_actor_profile_id uuid,
  p_action           text,
  p_entity_table     text,
  p_entity_id        uuid,
  p_before           jsonb default null,
  p_after            jsonb default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (school_id, actor_profile_id, action, entity_table, entity_id, before, after)
  values (p_school_id, p_actor_profile_id, p_action, p_entity_table, p_entity_id, p_before, p_after);
end;
$$;

comment on function public.write_audit_log(uuid, uuid, text, text, uuid, jsonb, jsonb) is
  'SECURITY DEFINER insertion point for audit_log, called explicitly from inside the privileged RPCs below. Not granted to authenticated directly — only reachable from another SECURITY DEFINER function''s own body, the same trust boundary admin_create_user already relies on for auth.users writes.';

-- Explicit revoke-then-grant, matching the documented pattern from
-- 20260827090000_guardian_invitations.sql — a plain `create function`
-- alone does not reliably prevent PUBLIC/anon execute.
revoke execute on function public.write_audit_log(uuid, uuid, text, text, uuid, jsonb, jsonb) from public;
-- Intentionally NOT granted to `authenticated` — this function is called
-- only from inside other SECURITY DEFINER functions' own bodies (which run
-- with the *defining* role's privileges, not the caller's), never directly
-- by a client.

-- ---------------------------------------------------------------------------
-- audit_log_from_trigger — the narrow-allowlist trigger insertion point,
-- attached below to exactly two tables (learner_fee_refunds,
-- learner_fee_adjustments), not generically.

create or replace function public.audit_log_from_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_entity_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if tg_op = 'DELETE' then
    v_school_id := old.school_id;
    v_entity_id := old.id;
    v_before := to_jsonb(old);
    v_after := null;
  else
    v_school_id := new.school_id;
    v_entity_id := new.id;
    v_after := to_jsonb(new);
    v_before := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  end if;

  insert into public.audit_log (school_id, actor_profile_id, action, entity_table, entity_id, before, after)
  values (v_school_id, auth.uid(), lower(tg_op) || '_' || tg_table_name, tg_table_name, v_entity_id, v_before, v_after);

  return null; -- AFTER trigger — return value is ignored either way.
end;
$$;

comment on function public.audit_log_from_trigger() is
  'Generic AFTER INSERT/UPDATE/DELETE trigger body — attached only to tables explicitly listed in this migration (an allowlist), not applied blanket-wide. auth.uid() is correct here (unlike write_audit_log''s explicit p_actor_profile_id parameter) because a trigger fires inside the calling client''s own request, which does carry a JWT.';

create trigger learner_fee_refunds_audit_log
  after insert or update on public.learner_fee_refunds
  for each row
  execute function public.audit_log_from_trigger();

create trigger learner_fee_adjustments_audit_log
  after insert or update on public.learner_fee_adjustments
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- RLS — readable only by school_owner/principal/platform admin for their
-- own tenant. No INSERT/UPDATE/DELETE policy for `authenticated` at all.

alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;

create policy audit_log_select on public.audit_log
  for select to authenticated using (
    (school_id = public.current_tenant_id() and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal'))
    or public.is_platform_admin()
  );

comment on policy audit_log_select on public.audit_log is
  'school_owner/principal see their own tenant''s trail; platform admins see everything, including school_id IS NULL platform-level actions (the tenant-scoped clause can never match a NULL school_id, so those rows are visible only via the is_platform_admin() branch).';

-- ---------------------------------------------------------------------------
-- Instrumented RPCs — re-declared via `create or replace function` with
-- their EXACT prior bodies (verified against the migrations that first
-- defined them) plus one added `perform public.write_audit_log(...)` call
-- each. Original migration files are untouched.

-- Was: 20260802151501_user_role_management.sql
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

  perform public.write_audit_log(
    v_target_tenant, auth.uid(), 'role_changed', 'profiles', p_user_id,
    jsonb_build_object('role', v_current_role), jsonb_build_object('role', p_new_role)
  );
end;
$$;

-- Was: 20260803160000_employee_management.sql
create or replace function public.terminate_employee(
  p_employee_id uuid,
  p_termination_date date
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_profile_id uuid;
  v_result public.employees;
begin
  select school_id, profile_id into v_school_id, v_profile_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this school';
  end if;

  update public.employees
    set employment_status = 'terminated', termination_date = p_termination_date
    where id = p_employee_id
    returning * into v_result;

  if v_profile_id is not null then
    update public.profiles set status = 'inactive' where id = v_profile_id;
  end if;

  perform public.write_audit_log(
    v_school_id, auth.uid(), 'employee_terminated', 'employees', p_employee_id,
    null, jsonb_build_object('employment_status', 'terminated', 'termination_date', p_termination_date)
  );

  return v_result;
end;
$$;

-- Was: 20260803160000_employee_management.sql
create or replace function public.reactivate_employee(p_employee_id uuid)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_result public.employees;
begin
  select school_id into v_school_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this school';
  end if;

  update public.employees
    set employment_status = 'active', termination_date = null
    where id = p_employee_id
    returning * into v_result;

  perform public.write_audit_log(
    v_school_id, auth.uid(), 'employee_reactivated', 'employees', p_employee_id,
    jsonb_build_object('employment_status', 'terminated'), jsonb_build_object('employment_status', 'active')
  );

  return v_result;
end;
$$;

-- Was: 20260803190000_learner_management.sql
create or replace function public.change_learner_status(
  p_learner_id uuid,
  p_new_status public.learner_status,
  p_reason text default null
)
returns public.learners
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_old_status public.learner_status;
  v_result public.learners;
begin
  select school_id, status into v_school_id, v_old_status from public.learners where id = p_learner_id;
  if not found then
    raise exception 'not_found: no learner %', p_learner_id;
  end if;

  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage learners for this school';
  end if;

  update public.learners
    set status = p_new_status, status_reason = p_reason
    where id = p_learner_id
    returning * into v_result;

  perform public.write_audit_log(
    v_school_id, auth.uid(), 'learner_status_changed', 'learners', p_learner_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status, 'reason', p_reason)
  );

  return v_result;
end;
$$;

-- Was: 20260803190000_learner_management.sql
create or replace function public.promote_learner(
  p_learner_id uuid,
  p_new_academic_year_id uuid,
  p_new_grade_id uuid,
  p_new_class_id uuid
)
returns public.learner_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_prior_enrollment_id uuid;
  v_result public.learner_enrollments;
begin
  select school_id into v_school_id from public.learners where id = p_learner_id;
  if not found then
    raise exception 'not_found: no learner %', p_learner_id;
  end if;

  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage learners for this school';
  end if;

  select id into v_prior_enrollment_id
    from public.learner_enrollments
    where learner_id = p_learner_id and enrollment_status = 'enrolled'
    order by created_at desc
    limit 1;

  if v_prior_enrollment_id is not null then
    update public.learner_enrollments set enrollment_status = 'promoted' where id = v_prior_enrollment_id;
  end if;

  insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date)
  values (v_school_id, p_learner_id, p_new_academic_year_id, p_new_grade_id, p_new_class_id, current_date)
  returning * into v_result;

  perform public.write_audit_log(
    v_school_id, auth.uid(), 'learner_promoted', 'learner_enrollments', v_result.id,
    null, jsonb_build_object('academic_year_id', p_new_academic_year_id, 'grade_id', p_new_grade_id, 'class_id', p_new_class_id)
  );

  return v_result;
end;
$$;
