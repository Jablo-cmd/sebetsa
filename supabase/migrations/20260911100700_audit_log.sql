-- Sebetsa Phase C — Audit Log Foundation
-- Pattern reused from Funda360's audit_log.sql: append-only, written only by
-- SECURITY DEFINER functions (never by a direct client INSERT), so a
-- compromised session can never forge or tamper with the trail.

create table public.audit_log (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid references public.organizations (id) on delete cascade,
  actor_profile_id   uuid references public.profiles (id) on delete set null,
  action             text not null check (char_length(action) > 0),
  entity_table       text not null check (char_length(entity_table) > 0),
  entity_id          uuid not null,
  before             jsonb,
  after              jsonb,
  created_at         timestamptz not null default now()
);

comment on table public.audit_log is 'Append-only audit trail for sensitive/privileged actions. tenant_id is NULL for platform-level actions. No UPDATE/DELETE policy, and no INSERT policy for `authenticated` — every row comes from a SECURITY DEFINER function.';

create index audit_log_tenant_id_idx on public.audit_log (tenant_id);
create index audit_log_entity_idx on public.audit_log (entity_table, entity_id);
create index audit_log_actor_idx on public.audit_log (actor_profile_id);
create index audit_log_created_at_idx on public.audit_log (created_at);

create or replace function public.write_audit_log(
  p_tenant_id        uuid,
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
  insert into public.audit_log (tenant_id, actor_profile_id, action, entity_table, entity_id, before, after)
  values (p_tenant_id, p_actor_profile_id, p_action, p_entity_table, p_entity_id, p_before, p_after);
end;
$$;

comment on function public.write_audit_log(uuid, uuid, text, text, uuid, jsonb, jsonb) is
  'SECURITY DEFINER insertion point, called only from inside other SECURITY DEFINER RPCs — not granted to authenticated directly.';

revoke execute on function public.write_audit_log(uuid, uuid, text, text, uuid, jsonb, jsonb) from public;

alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;

create policy audit_log_select on public.audit_log
  for select to authenticated using (
    (tenant_id = public.current_tenant_id() and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'organization_administrator')
    or public.is_platform_admin()
  );

-- ---------------------------------------------------------------------------
-- Instrument admin_update_user_role (20260911100300) with an audit call.

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

-- ---------------------------------------------------------------------------
-- Employee lifecycle RPCs (audited), mirroring Funda360's
-- terminate_employee/reactivate_employee shape.

create or replace function public.can_manage_employees(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('organization_administrator', 'operations_manager', 'hr_user')
    )
    or public.is_platform_admin()
$$;

grant execute on function public.can_manage_employees(uuid) to authenticated;

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
  v_tenant_id uuid;
  v_profile_id uuid;
  v_result public.employees;
begin
  select tenant_id, profile_id into v_tenant_id, v_profile_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this organization';
  end if;

  update public.employees
    set employment_status = 'terminated', employment_end_date = p_termination_date
    where id = p_employee_id
    returning * into v_result;

  if v_profile_id is not null then
    update public.profiles set status = 'inactive' where id = v_profile_id;
  end if;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'employee_terminated', 'employees', p_employee_id,
    null, jsonb_build_object('employment_status', 'terminated', 'employment_end_date', p_termination_date)
  );

  return v_result;
end;
$$;

create or replace function public.reactivate_employee(p_employee_id uuid)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.employees;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this organization';
  end if;

  update public.employees
    set employment_status = 'active', employment_end_date = null
    where id = p_employee_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'employee_reactivated', 'employees', p_employee_id,
    jsonb_build_object('employment_status', 'terminated'), jsonb_build_object('employment_status', 'active')
  );

  return v_result;
end;
$$;

grant execute on function public.terminate_employee(uuid, date) to authenticated;
grant execute on function public.reactivate_employee(uuid) to authenticated;
