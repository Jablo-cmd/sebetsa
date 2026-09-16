-- Sebetsa Phase Q (2 of 2) — Scope of Work Engine.
--
-- Models what a cleaning contract actually commits to, structurally:
-- CONTRACT -> SITE -> AREA -> TASK DEFINITION, not a free-text description.
-- Reuses the existing site/contract/task_templates infrastructure rather
-- than duplicating it: `site_areas` is the one new structural concept
-- (nothing in the schema modeled "area" before this); `scope_of_work_items`
-- is the structured task definition per area; a scope item is turned into
-- a real, existing `task_templates` row (Phase K) by an explicit RPC —
-- the same generate_recurring_tasks()/tasks pipeline downstream keeps
-- working completely unchanged, this just gives it a structured, contract-
-- scoped authoring source instead of a manager typing templates ad hoc.

-- ---------------------------------------------------------------------------
-- site_areas: a named zone within a site (Reception, Bathrooms, Boardroom).

create table public.site_areas (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  site_id     uuid not null references public.sites (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  description text,
  sort_order  integer not null default 0,
  status      public.entity_status not null default 'active',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (site_id, name)
);

create index site_areas_tenant_id_idx on public.site_areas (tenant_id);
create index site_areas_site_id_idx on public.site_areas (site_id, sort_order);

create trigger site_areas_set_updated_at
  before update on public.site_areas
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_site_area_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger site_areas_validate_tenant_refs
  before insert or update on public.site_areas
  for each row
  execute function public.validate_site_area_tenant_refs();

alter table public.site_areas enable row level security;
alter table public.site_areas force row level security;

create policy site_areas_select_within_tenant on public.site_areas for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy site_areas_write_by_manager on public.site_areas for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger site_areas_audit_log
  after insert or update on public.site_areas
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- scope_of_work_items: the structured task definition for one area, scoped
-- to a specific contract (the same physical area can be scoped differently
-- under a renewed/renegotiated contract, so this is contract-owned, not
-- site_area-owned).

create table public.scope_of_work_items (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  contract_id           uuid not null references public.contracts (id) on delete cascade,
  site_area_id          uuid not null references public.site_areas (id) on delete cascade,
  task_name             text not null check (char_length(task_name) > 0),
  frequency             text check (frequency is null or frequency in ('daily', 'weekly', 'monthly', 'once_off')),
  estimated_minutes     integer check (estimated_minutes is null or estimated_minutes > 0),
  assigned_role         text,
  required_equipment    text,
  required_consumables  text,
  ppe_notes             text,
  instructions          text,
  requires_evidence     boolean not null default false,
  priority              public.task_priority not null default 'normal',
  status                public.entity_status not null default 'active',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.scope_of_work_items is
  'The structured "what, how often, by whom" for one area under one contract. Feeds task_templates via create_task_template_from_scope_item() — never a second, parallel task system.';

create index scope_of_work_items_tenant_id_idx on public.scope_of_work_items (tenant_id);
create index scope_of_work_items_contract_id_idx on public.scope_of_work_items (contract_id);
create index scope_of_work_items_site_area_id_idx on public.scope_of_work_items (site_area_id);

create trigger scope_of_work_items_set_updated_at
  before update on public.scope_of_work_items
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_scope_of_work_item_tenant_refs()
returns trigger
language plpgsql
as $$
declare
  v_area_site_id uuid;
begin
  if not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  select site_id into v_area_site_id from public.site_areas where id = new.site_area_id and tenant_id = new.tenant_id;
  if v_area_site_id is null then
    raise exception 'cross_tenant_reference: site area % does not belong to tenant %', new.site_area_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.contract_sites where contract_id = new.contract_id and site_id = v_area_site_id) then
    raise exception 'invalid_reference: site area % belongs to a site not covered by contract %', new.site_area_id, new.contract_id;
  end if;
  return new;
end;
$$;

create trigger scope_of_work_items_validate_tenant_refs
  before insert or update on public.scope_of_work_items
  for each row
  execute function public.validate_scope_of_work_item_tenant_refs();

alter table public.scope_of_work_items enable row level security;
alter table public.scope_of_work_items force row level security;

create policy scope_of_work_items_select_within_tenant on public.scope_of_work_items for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy scope_of_work_items_write_by_manager on public.scope_of_work_items for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger scope_of_work_items_audit_log
  after insert or update on public.scope_of_work_items
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Traceability link on the existing task_templates table (Phase K) — purely
-- additive, nullable, changes no existing behaviour of generate_recurring_tasks().

alter table public.task_templates
  add column scope_of_work_item_id uuid references public.scope_of_work_items (id) on delete set null;

create index task_templates_scope_of_work_item_id_idx on public.task_templates (scope_of_work_item_id);

-- ---------------------------------------------------------------------------
-- create_task_template_from_scope_item: explicit, one-scope-item-at-a-time
-- conversion into a real task_templates row — matches this codebase's own
-- "manually triggered, cron-ready, never silent magic" posture
-- (generate_recurring_tasks, escalate_overdue_tasks, the *_expiry sweeps).

create or replace function public.create_task_template_from_scope_item(
  p_scope_of_work_item_id uuid,
  p_default_assignee_id   uuid default null,
  p_default_team_id       uuid default null
)
returns public.task_templates
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.scope_of_work_items;
  v_site_id uuid;
  v_recurrence text;
  v_result public.task_templates;
begin
  select * into v_item from public.scope_of_work_items where id = p_scope_of_work_item_id;
  if not found then
    raise exception 'not_found: no scope of work item %', p_scope_of_work_item_id;
  end if;

  if not public.can_manage_org_structure(v_item.tenant_id) then
    raise exception 'insufficient_privilege: cannot generate a task template for this tenant';
  end if;

  select site_id into v_site_id from public.site_areas where id = v_item.site_area_id;

  -- task_templates.recurrence_frequency only accepts daily/weekly/monthly;
  -- a once_off scope item becomes a non-recurring template (frequency null).
  v_recurrence := case when v_item.frequency in ('daily', 'weekly', 'monthly') then v_item.frequency else null end;

  insert into public.task_templates (
    tenant_id, site_id, title, description, instructions, priority,
    expected_duration_minutes, requires_evidence, default_assignee_id, default_team_id,
    recurrence_frequency, scope_of_work_item_id
  ) values (
    v_item.tenant_id, v_site_id, v_item.task_name, v_item.required_equipment,
    v_item.instructions, v_item.priority, v_item.estimated_minutes, v_item.requires_evidence,
    p_default_assignee_id, p_default_team_id, v_recurrence, v_item.id
  )
  returning * into v_result;

  perform public.write_audit_log(v_item.tenant_id, auth.uid(), 'task_template_created_from_scope', 'task_templates', v_result.id, null, jsonb_build_object('scope_of_work_item_id', v_item.id));

  return v_result;
end;
$$;

comment on function public.create_task_template_from_scope_item(uuid, uuid, uuid) is
  'Turns one scope_of_work_items row into a real task_templates row (Phase K) — the existing generate_recurring_tasks()/task pipeline then works completely unchanged. Explicit, one item at a time; no automatic/hidden generation.';

revoke execute on function public.create_task_template_from_scope_item(uuid, uuid, uuid) from public, anon;
grant execute on function public.create_task_template_from_scope_item(uuid, uuid, uuid) to authenticated;
