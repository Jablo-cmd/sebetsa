-- Sebetsa security hardening: privilege lock-down, separation of duties,
-- scope-aware authorization, audit immutability, FK indexes.
--
-- 1. Audit trail: security/business split, request correlation, append-only.
-- 2. Separation of duties: one rule registry + one assertion function, applied
--    by AFTER UPDATE guards so direct writes and RPCs are covered alike.
-- 3. Scope-aware authorization: user_scopes (region / site / team) with
--    RESTRICTIVE policies narrowing regional_manager, site_manager and
--    supervisor to their assigned scope on operational tables.
-- 4. Missing foreign-key indexes.
-- 5. Grants: anon loses all public table/function access; authenticated loses
--    TRUNCATE/REFERENCES/TRIGGER and internal helpers; defaults tightened.

-- ---------------------------------------------------------------------------
-- 1. Audit log
-- ---------------------------------------------------------------------------

alter table public.audit_log
  add column category text not null default 'business' check (category in ('business', 'security')),
  add column outcome text not null default 'success' check (outcome in ('success', 'denied', 'failure')),
  add column request_id text,
  add column metadata jsonb;

comment on column public.audit_log.category is
  'security = identity/privilege/tenant/scope changes; business = operational record changes.';
comment on column public.audit_log.request_id is
  'x-request-id of the originating PostgREST request when the client supplied one.';

create index audit_log_tenant_created_idx on public.audit_log (tenant_id, created_at desc);
create index audit_log_category_idx on public.audit_log (category, created_at desc);

create or replace function public.audit_log_enrich()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_headers text := nullif(current_setting('request.headers', true), '');
begin
  if new.request_id is null and v_headers is not null then
    begin
      new.request_id := left(nullif(v_headers::jsonb ->> 'x-request-id', ''), 128);
    exception when others then
      new.request_id := null;
    end;
  end if;

  if new.category = 'business'
     and (new.action ~ '^(role_|user_|tenant_|login_|mfa_|permission_|scope_|provision)'
          or new.entity_table = 'user_scopes') then
    new.category := 'security';
  end if;
  return new;
end;
$$;

create trigger audit_log_enrich_trigger
  before insert on public.audit_log
  for each row execute function public.audit_log_enrich();

-- Append-only. UPDATE is only tolerated for the FK "on delete set null"
-- housekeeping of actor/tenant columns; DELETE only for tenant cascade or the
-- retention function below. Everything else — including service role — fails.
create or replace function public.audit_log_block_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'audit_log_immutable: audit history cannot be truncated';
  end if;

  if tg_op = 'UPDATE' then
    if pg_trigger_depth() > 1
       and (to_jsonb(new) - 'actor_profile_id' - 'tenant_id') = (to_jsonb(old) - 'actor_profile_id' - 'tenant_id') then
      return new;
    end if;
    raise exception 'audit_log_immutable: audit history cannot be modified';
  end if;

  if tg_op = 'DELETE' then
    if coalesce(current_setting('app.audit_retention', true), '') = 'on' or pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception 'audit_log_immutable: audit history cannot be deleted';
  end if;

  return null;
end;
$$;

create trigger audit_log_block_mutation_trigger
  before update or delete on public.audit_log
  for each row execute function public.audit_log_block_mutation();

create trigger audit_log_block_truncate_trigger
  before truncate on public.audit_log
  for each statement execute function public.audit_log_block_mutation();

-- Retention: service role only, never newer than one year.
create or replace function public.purge_audit_log(p_older_than interval default interval '7 years')
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  if p_older_than < interval '365 days' then
    raise exception 'invalid_configuration: audit retention cannot be shorter than 365 days';
  end if;
  perform set_config('app.audit_retention', 'on', true);
  delete from public.audit_log where created_at < now() - p_older_than;
  get diagnostics v_deleted = row_count;
  perform set_config('app.audit_retention', 'off', true);
  return v_deleted;
end;
$$;

-- Security events raised by service-role workers/Edge Functions.
create or replace function public.write_security_audit_event(
  p_tenant_id uuid,
  p_actor_profile_id uuid,
  p_action text,
  p_entity_table text,
  p_entity_id uuid,
  p_outcome text default 'success',
  p_metadata jsonb default null,
  p_request_id text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (tenant_id, actor_profile_id, action, entity_table, entity_id, category, outcome, metadata, request_id)
  values (p_tenant_id, p_actor_profile_id, p_action, p_entity_table, p_entity_id, 'security', p_outcome, p_metadata, p_request_id);
end;
$$;

revoke insert, update, delete, truncate on public.audit_log from authenticated;

-- ---------------------------------------------------------------------------
-- 2. Separation of duties
-- ---------------------------------------------------------------------------

create table public.sod_rules (
  rule_key text primary key,
  description text not null,
  enforced boolean not null default true
);

alter table public.sod_rules enable row level security;
alter table public.sod_rules force row level security;
create policy sod_rules_select on public.sod_rules for select to authenticated using (true);
revoke insert, update, delete on public.sod_rules from authenticated;

insert into public.sod_rules (rule_key, description) values
  ('leave.decide',                'The employee a leave request concerns cannot approve, reject or revoke it.'),
  ('attendance_correction.decide','The requester, or the employee whose attendance is corrected, cannot decide the correction.'),
  ('document.verify',             'The uploader, or the employee a document belongs to, cannot verify or reject it.'),
  ('compliance.verify',           'The person responsible for a compliance record cannot verify it.'),
  ('incident.close',              'The person who reported an incident cannot close it.'),
  ('incident_action.verify',      'The owner of a corrective action cannot verify it.'),
  ('task.verify',                 'The person who completed a task, or its assignee, cannot verify it.'),
  ('skill.verify',                'An employee cannot verify their own skill.'),
  ('qualification.verify',        'An employee cannot verify their own qualification.'),
  ('procurement.decide',          'The requester cannot approve or reject their own procurement request.'),
  ('role.assign',                 'A user cannot change their own role.'),
  ('scope.assign',                'A user cannot grant themselves an operational scope.');

create or replace function public.employee_profile_id(p_employee_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select profile_id from public.employees where id = p_employee_id
$$;

-- Raises when the acting user (auth.uid()) is one of the profiles the record
-- concerns. A NULL auth.uid() (service role, scheduled jobs) is not a person
-- acting and is not blocked.
create or replace function public.assert_separation_of_duties(p_rule text, p_subjects uuid[])
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_enforced boolean;
begin
  if v_actor is null then
    return;
  end if;
  select enforced into v_enforced from public.sod_rules where rule_key = p_rule;
  if coalesce(v_enforced, true) is false then
    return;
  end if;
  if v_actor = any (p_subjects) then
    raise exception 'separation_of_duties: % — you cannot act on a record you raised or that concerns you', p_rule
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.sod_guard_leave_requests()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected', 'revoked') then
    perform public.assert_separation_of_duties('leave.decide', array[public.employee_profile_id(new.employee_id)]);
  end if;
  return null;
end; $$;
create trigger leave_requests_sod_guard after update on public.leave_requests
  for each row execute function public.sod_guard_leave_requests();

create or replace function public.sod_guard_attendance_corrections()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    perform public.assert_separation_of_duties(
      'attendance_correction.decide',
      array[
        new.requested_by,
        (select public.employee_profile_id(ar.employee_id) from public.attendance_records ar where ar.id = new.attendance_record_id)
      ]
    );
  end if;
  return null;
end; $$;
create trigger attendance_corrections_sod_guard after update on public.attendance_corrections
  for each row execute function public.sod_guard_attendance_corrections();

create or replace function public.sod_guard_employee_documents()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.status is distinct from old.status and new.status in ('verified', 'rejected'))
     or (new.verified_by is distinct from old.verified_by and new.verified_by is not null) then
    perform public.assert_separation_of_duties(
      'document.verify', array[new.uploaded_by, public.employee_profile_id(new.employee_id)]);
  end if;
  return null;
end; $$;
create trigger employee_documents_sod_guard after update on public.employee_documents
  for each row execute function public.sod_guard_employee_documents();

create or replace function public.sod_guard_compliance_records()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.verified_by is distinct from old.verified_by and new.verified_by is not null then
    perform public.assert_separation_of_duties('compliance.verify', array[new.responsible_profile_id]);
  end if;
  return null;
end; $$;
create trigger compliance_records_sod_guard after update on public.compliance_records
  for each row execute function public.sod_guard_compliance_records();

create or replace function public.sod_guard_incidents()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status = 'closed' then
    perform public.assert_separation_of_duties('incident.close', array[new.reported_by]);
  end if;
  return null;
end; $$;
create trigger incidents_sod_guard after update on public.incidents
  for each row execute function public.sod_guard_incidents();

create or replace function public.sod_guard_incident_actions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.verified_by is distinct from old.verified_by and new.verified_by is not null then
    perform public.assert_separation_of_duties('incident_action.verify', array[new.owner_profile_id]);
  end if;
  return null;
end; $$;
create trigger incident_actions_sod_guard after update on public.incident_actions
  for each row execute function public.sod_guard_incident_actions();

create or replace function public.sod_guard_tasks()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status = 'verified' then
    perform public.assert_separation_of_duties(
      'task.verify', array[new.completed_by, public.employee_profile_id(new.assignee_id)]);
  end if;
  return null;
end; $$;
create trigger tasks_sod_guard after update on public.tasks
  for each row execute function public.sod_guard_tasks();

create or replace function public.sod_guard_employee_skills()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.verified_by is distinct from old.verified_by and new.verified_by is not null then
    perform public.assert_separation_of_duties('skill.verify', array[public.employee_profile_id(new.employee_id)]);
  end if;
  return null;
end; $$;
create trigger employee_skills_sod_guard after update on public.employee_skills
  for each row execute function public.sod_guard_employee_skills();

create or replace function public.sod_guard_employee_qualifications()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.verified_by is distinct from old.verified_by and new.verified_by is not null then
    perform public.assert_separation_of_duties('qualification.verify', array[public.employee_profile_id(new.employee_id)]);
  end if;
  return null;
end; $$;
create trigger employee_qualifications_sod_guard after update on public.employee_qualifications
  for each row execute function public.sod_guard_employee_qualifications();

create or replace function public.sod_guard_procurement_requests()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    perform public.assert_separation_of_duties('procurement.decide', array[new.requested_by]);
  end if;
  return null;
end; $$;
create trigger procurement_requests_sod_guard after update on public.procurement_requests
  for each row execute function public.sod_guard_procurement_requests();

-- Role assignment: nobody changes their own role.
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

  perform public.assert_separation_of_duties('role.assign', array[p_user_id]);

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
-- 3. Scope-aware authorization
-- ---------------------------------------------------------------------------

create table public.user_scopes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  scope_type text not null check (scope_type in ('region', 'site', 'team')),
  scope_id uuid not null,
  granted_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (profile_id, scope_type, scope_id)
);

comment on table public.user_scopes is
  'Operational scope assignments. regional_manager, site_manager and supervisor only reach site-bound operational records inside a region/site/team assigned here. Written only by grant_user_scope()/revoke_user_scope().';

create index user_scopes_tenant_idx on public.user_scopes (tenant_id);
create index user_scopes_profile_idx on public.user_scopes (profile_id);
create index user_scopes_scope_idx on public.user_scopes (scope_type, scope_id);
create index user_scopes_granted_by_idx on public.user_scopes (granted_by);

alter table public.user_scopes enable row level security;
alter table public.user_scopes force row level security;

create policy user_scopes_select on public.user_scopes
  for select to authenticated using (
    profile_id = auth.uid()
    or public.can_manage_org_structure(tenant_id)
  );

revoke insert, update, delete on public.user_scopes from authenticated;

create or replace function public.is_scoped_role()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('regional_manager', 'site_manager', 'supervisor')
$$;

-- True when the caller may reach a record bound to p_site_id in p_tenant_id.
-- Tenant-wide roles: any site in their tenant. Scoped roles: only sites inside
-- an assigned site, team (via its site) or region. Fails closed for a scoped
-- role with no assignments. NULL site = not site-bound = no scope restriction.
create or replace function public.can_access_site(p_tenant_id uuid, p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.is_platform_admin() then true
    when p_tenant_id is distinct from public.current_tenant_id() then false
    when not public.is_scoped_role() then true
    when p_site_id is null then true
    else exists (
      select 1
      from public.user_scopes us
      where us.profile_id = auth.uid()
        and us.tenant_id = p_tenant_id
        and (
          (us.scope_type = 'site' and us.scope_id = p_site_id)
          or (us.scope_type = 'region' and us.scope_id = (select s.region_id from public.sites s where s.id = p_site_id))
          or (us.scope_type = 'team' and exists (
                select 1 from public.teams t where t.id = us.scope_id and t.site_id = p_site_id))
        )
    )
  end
$$;

create or replace function public.is_own_employee(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.employees e where e.id = p_employee_id and e.profile_id = auth.uid())
$$;

create or replace function public.grant_user_scope(p_profile_id uuid, p_scope_type text, p_scope_id uuid)
returns public.user_scopes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_ok boolean;
  v_row public.user_scopes;
begin
  select tenant_id into v_tenant from public.profiles where id = p_profile_id;
  if not found then
    raise exception 'not_found: no profile %', p_profile_id;
  end if;
  if not public.can_manage_org_structure(v_tenant) then
    raise exception 'insufficient_privilege: cannot assign scopes in this tenant';
  end if;
  perform public.assert_separation_of_duties('scope.assign', array[p_profile_id]);

  if p_scope_type = 'region' then
    select exists (select 1 from public.regions where id = p_scope_id and tenant_id = v_tenant) into v_ok;
  elsif p_scope_type = 'site' then
    select exists (select 1 from public.sites where id = p_scope_id and tenant_id = v_tenant) into v_ok;
  elsif p_scope_type = 'team' then
    select exists (select 1 from public.teams where id = p_scope_id and tenant_id = v_tenant) into v_ok;
  else
    raise exception 'invalid_status: unknown scope type %', p_scope_type;
  end if;
  if not v_ok then
    raise exception 'cross_tenant_reference: % % does not belong to tenant %', p_scope_type, p_scope_id, v_tenant;
  end if;

  insert into public.user_scopes (tenant_id, profile_id, scope_type, scope_id, granted_by)
  values (v_tenant, p_profile_id, p_scope_type, p_scope_id, auth.uid())
  on conflict (profile_id, scope_type, scope_id) do update set granted_by = excluded.granted_by
  returning * into v_row;

  perform public.write_audit_log(v_tenant, auth.uid(), 'scope_granted', 'user_scopes', v_row.id, null, to_jsonb(v_row));
  return v_row;
end;
$$;

create or replace function public.revoke_user_scope(p_scope_row_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.user_scopes;
begin
  select * into v_row from public.user_scopes where id = p_scope_row_id for update;
  if not found then
    raise exception 'not_found: no scope assignment %', p_scope_row_id;
  end if;
  if not public.can_manage_org_structure(v_row.tenant_id) then
    raise exception 'insufficient_privilege: cannot assign scopes in this tenant';
  end if;
  delete from public.user_scopes where id = p_scope_row_id;
  perform public.write_audit_log(v_row.tenant_id, auth.uid(), 'scope_revoked', 'user_scopes', v_row.id, to_jsonb(v_row), null);
end;
$$;

-- RESTRICTIVE policies: ANDed with the existing permissive ones, so they can
-- only narrow access, and only for scoped roles (everyone else passes).
create policy scope_restrict_incidents on public.incidents
  as restrictive for all to authenticated
  using (reported_by = auth.uid() or public.can_access_site(tenant_id, site_id))
  with check (reported_by = auth.uid() or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_compliance_records on public.compliance_records
  as restrictive for all to authenticated
  using (responsible_profile_id = auth.uid() or public.can_access_site(tenant_id, site_id))
  with check (responsible_profile_id = auth.uid() or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_procurement_requests on public.procurement_requests
  as restrictive for all to authenticated
  using (requested_by = auth.uid() or public.can_access_site(tenant_id, site_id))
  with check (requested_by = auth.uid() or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_assets on public.assets
  as restrictive for all to authenticated
  using (public.is_own_employee(custodian_employee_id) or public.can_access_site(tenant_id, site_id))
  with check (public.is_own_employee(custodian_employee_id) or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_inventory_movements on public.inventory_movements
  as restrictive for all to authenticated
  using (performed_by = auth.uid() or public.can_access_site(tenant_id, site_id))
  with check (performed_by = auth.uid() or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_shifts on public.shifts
  as restrictive for all to authenticated
  using (public.is_own_employee(employee_id) or public.can_access_site(tenant_id, site_id))
  with check (public.is_own_employee(employee_id) or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_attendance_records on public.attendance_records
  as restrictive for all to authenticated
  using (public.is_own_employee(employee_id) or public.can_access_site(tenant_id, site_id))
  with check (public.is_own_employee(employee_id) or public.can_access_site(tenant_id, site_id));

create policy scope_restrict_tasks on public.tasks
  as restrictive for all to authenticated
  using (public.is_own_employee(assignee_id) or public.can_access_site(tenant_id, site_id))
  with check (public.is_own_employee(assignee_id) or public.can_access_site(tenant_id, site_id));

-- ---------------------------------------------------------------------------
-- 4. Foreign-key indexes
-- ---------------------------------------------------------------------------

create index if not exists asset_assignments_assigned_by_fk_idx on public.asset_assignments (assigned_by);
create index if not exists asset_assignments_assigned_to_employee_id_fk_idx on public.asset_assignments (assigned_to_employee_id);
create index if not exists asset_assignments_assigned_to_site_id_fk_idx on public.asset_assignments (assigned_to_site_id);
create index if not exists asset_assignments_assigned_to_team_id_fk_idx on public.asset_assignments (assigned_to_team_id);
create index if not exists asset_assignments_tenant_id_fk_idx on public.asset_assignments (tenant_id);
create index if not exists asset_maintenance_records_performed_by_fk_idx on public.asset_maintenance_records (performed_by);
create index if not exists asset_maintenance_records_tenant_id_fk_idx on public.asset_maintenance_records (tenant_id);
create index if not exists attendance_corrections_requested_by_fk_idx on public.attendance_corrections (requested_by);
create index if not exists attendance_corrections_reviewed_by_fk_idx on public.attendance_corrections (reviewed_by);
create index if not exists attendance_records_recorded_by_fk_idx on public.attendance_records (recorded_by);
create index if not exists compliance_records_client_id_fk_idx on public.compliance_records (client_id);
create index if not exists compliance_records_contract_id_fk_idx on public.compliance_records (contract_id);
create index if not exists compliance_records_site_id_fk_idx on public.compliance_records (site_id);
create index if not exists compliance_records_verified_by_fk_idx on public.compliance_records (verified_by);
create index if not exists compliance_requirements_created_by_fk_idx on public.compliance_requirements (created_by);
create index if not exists contract_documents_uploaded_by_fk_idx on public.contract_documents (uploaded_by);
create index if not exists contracts_responsible_manager_id_fk_idx on public.contracts (responsible_manager_id);
create index if not exists development_actions_owner_profile_id_fk_idx on public.development_actions (owner_profile_id);
create index if not exists development_actions_review_id_fk_idx on public.development_actions (review_id);
create index if not exists employee_documents_supersedes_document_id_fk_idx on public.employee_documents (supersedes_document_id);
create index if not exists employee_documents_uploaded_by_fk_idx on public.employee_documents (uploaded_by);
create index if not exists employee_documents_verified_by_fk_idx on public.employee_documents (verified_by);
create index if not exists employee_qualifications_evidence_document_id_fk_idx on public.employee_qualifications (evidence_document_id);
create index if not exists employee_qualifications_verified_by_fk_idx on public.employee_qualifications (verified_by);
create index if not exists employee_skills_evidence_document_id_fk_idx on public.employee_skills (evidence_document_id);
create index if not exists employee_skills_skill_id_fk_idx on public.employee_skills (skill_id);
create index if not exists employee_skills_verified_by_fk_idx on public.employee_skills (verified_by);
create index if not exists employees_position_id_fk_idx on public.employees (position_id);
create index if not exists employees_region_id_fk_idx on public.employees (region_id);
create index if not exists incident_actions_verified_by_fk_idx on public.incident_actions (verified_by);
create index if not exists incident_affected_employees_tenant_id_fk_idx on public.incident_affected_employees (tenant_id);
create index if not exists incidents_closed_by_fk_idx on public.incidents (closed_by);
create index if not exists incidents_contract_id_fk_idx on public.incidents (contract_id);
create index if not exists incidents_reported_by_fk_idx on public.incidents (reported_by);
create index if not exists inventory_movements_performed_by_fk_idx on public.inventory_movements (performed_by);
create index if not exists inventory_movements_site_id_fk_idx on public.inventory_movements (site_id);
create index if not exists leave_balance_transactions_created_by_fk_idx on public.leave_balance_transactions (created_by);
create index if not exists leave_balance_transactions_leave_type_id_fk_idx on public.leave_balance_transactions (leave_type_id);
create index if not exists leave_balances_leave_type_id_fk_idx on public.leave_balances (leave_type_id);
create index if not exists leave_requests_cancelled_by_fk_idx on public.leave_requests (cancelled_by);
create index if not exists leave_requests_decided_by_fk_idx on public.leave_requests (decided_by);
create index if not exists performance_reviews_reviewer_profile_id_fk_idx on public.performance_reviews (reviewer_profile_id);
create index if not exists procurement_requests_approved_by_fk_idx on public.procurement_requests (approved_by);
create index if not exists procurement_requests_site_id_fk_idx on public.procurement_requests (site_id);
create index if not exists shift_substitutions_original_employee_id_fk_idx on public.shift_substitutions (original_employee_id);
create index if not exists shift_substitutions_substitute_employee_id_fk_idx on public.shift_substitutions (substitute_employee_id);
create index if not exists shifts_supervisor_id_fk_idx on public.shifts (supervisor_id);
create index if not exists sla_definitions_site_id_fk_idx on public.sla_definitions (site_id);
create index if not exists sla_measurements_computed_by_fk_idx on public.sla_measurements (computed_by);
create index if not exists task_checklist_items_completed_by_fk_idx on public.task_checklist_items (completed_by);
create index if not exists task_comments_author_id_fk_idx on public.task_comments (author_id);
create index if not exists task_evidence_submitted_by_fk_idx on public.task_evidence (submitted_by);
create index if not exists task_templates_default_assignee_id_fk_idx on public.task_templates (default_assignee_id);
create index if not exists task_templates_default_team_id_fk_idx on public.task_templates (default_team_id);
create index if not exists tasks_completed_by_fk_idx on public.tasks (completed_by);
create index if not exists tasks_created_by_fk_idx on public.tasks (created_by);
create index if not exists tasks_supervisor_id_fk_idx on public.tasks (supervisor_id);
create index if not exists teams_lead_employee_id_fk_idx on public.teams (lead_employee_id);
create index if not exists training_enrollments_resulting_qualification_id_fk_idx on public.training_enrollments (resulting_qualification_id);
create index if not exists training_requirements_required_for_site_id_fk_idx on public.training_requirements (required_for_site_id);

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

-- Lock PUBLIC/anon out of everything in public, but first remember what
-- `authenticated` can execute today (explicitly or via PUBLIC) and restore
-- exactly that, so RLS helpers and client RPCs keep working.
do $$
declare
  r record;
  v_fns regprocedure[];
begin
  select coalesce(array_agg(p.oid::regprocedure), '{}')
    into v_fns
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind in ('f', 'p')
    and has_function_privilege('authenticated', p.oid, 'EXECUTE');

  revoke all on all tables in schema public from anon;
  revoke all on all sequences in schema public from anon;
  revoke execute on all functions in schema public from public, anon;
  revoke truncate, references, trigger on all tables in schema public from authenticated;
  revoke insert, update, delete on public.notification_deliveries from authenticated;

  for r in select unnest(v_fns) as fn loop
    execute format('grant execute on function %s to authenticated', r.fn);
  end loop;
end;
$$;

grant execute on all functions in schema public to service_role;

-- Internal helpers: never callable straight from the client.
revoke execute on function public.compute_attendance_metrics(uuid) from authenticated;
revoke execute on function public.assert_separation_of_duties(text, uuid[]) from authenticated;
revoke execute on function public.employee_profile_id(uuid) from authenticated;
revoke execute on function public.purge_audit_log(interval) from authenticated;
revoke execute on function public.write_security_audit_event(uuid, uuid, text, text, uuid, text, jsonb, text) from authenticated;

grant execute on function public.grant_user_scope(uuid, text, uuid) to authenticated;
grant execute on function public.revoke_user_scope(uuid) to authenticated;
grant execute on function public.is_scoped_role() to authenticated;
grant execute on function public.can_access_site(uuid, uuid) to authenticated;
grant execute on function public.is_own_employee(uuid) to authenticated;

-- Objects created by future migrations start closed to anon/PUBLIC.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from public, anon;
