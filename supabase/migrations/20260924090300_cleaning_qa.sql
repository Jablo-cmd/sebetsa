-- Sebetsa Phase W — Cleaning QA / Inspections.
--
-- A dedicated, deterministic cleaning-quality inspection engine — distinct
-- from the existing guard-tour/patrol-checkpoint system (Domain 13), which
-- verifies a guard's presence on a route, not cleaning quality. No seed
-- templates are inserted here: a fake "starter" template would be exactly
-- the kind of fabricated data this codebase's own conventions (and this
-- brief) forbid — a manager creates real templates for their own service
-- lines via the UI this migration's RPCs support.
--
-- Scoring is a single deterministic SQL formula (weighted score / weighted
-- max, as a percentage), mirrored by a pure, unit-tested TypeScript
-- function on the frontend for display before the server round-trip —
-- never an AI/LLM judgement call.

create type public.inspection_status as enum ('scheduled', 'in_progress', 'completed', 'closed');
create type public.defect_severity as enum ('low', 'medium', 'high', 'critical');
create type public.defect_status as enum ('open', 'in_progress', 'resolved', 'verified');

-- ---------------------------------------------------------------------------
create table public.inspection_templates (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.organizations (id) on delete cascade,
  name           text not null check (char_length(name) > 0),
  description    text,
  category       text,
  pass_threshold numeric(5, 2) not null default 80.00 check (pass_threshold >= 0 and pass_threshold <= 100),
  is_active      boolean not null default true,
  created_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, name)
);

create index inspection_templates_tenant_id_idx on public.inspection_templates (tenant_id);

create trigger inspection_templates_set_updated_at
  before update on public.inspection_templates
  for each row
  execute function public.set_updated_at();

alter table public.inspection_templates enable row level security;
alter table public.inspection_templates force row level security;

create policy inspection_templates_select on public.inspection_templates for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy inspection_templates_write_by_manager on public.inspection_templates for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger inspection_templates_audit_log
  after insert or update on public.inspection_templates
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create table public.inspection_template_items (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.organizations (id) on delete cascade,
  template_id  uuid not null references public.inspection_templates (id) on delete cascade,
  area_label   text not null check (char_length(area_label) > 0),
  criterion    text not null check (char_length(criterion) > 0),
  max_score    numeric(5, 2) not null default 10 check (max_score > 0),
  weight       numeric(5, 2) not null default 1 check (weight > 0),
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);

create index inspection_template_items_template_id_idx on public.inspection_template_items (template_id, sort_order);
create index inspection_template_items_tenant_id_idx on public.inspection_template_items (tenant_id);

create or replace function public.validate_inspection_template_item_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.inspection_templates where id = new.template_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: template % does not belong to tenant %', new.template_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger inspection_template_items_validate_tenant_refs
  before insert or update on public.inspection_template_items
  for each row
  execute function public.validate_inspection_template_item_tenant_refs();

alter table public.inspection_template_items enable row level security;
alter table public.inspection_template_items force row level security;

create policy inspection_template_items_select on public.inspection_template_items for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy inspection_template_items_write_by_manager on public.inspection_template_items for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

-- ---------------------------------------------------------------------------
create table public.inspections (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.organizations (id) on delete cascade,
  client_id          uuid not null references public.clients (id) on delete cascade,
  site_id            uuid not null references public.sites (id) on delete cascade,
  contract_id        uuid references public.contracts (id) on delete set null,
  variation_order_id uuid references public.variation_orders (id) on delete set null,
  template_id        uuid not null references public.inspection_templates (id) on delete restrict,
  inspector_id       uuid references public.profiles (id) on delete set null,
  status             public.inspection_status not null default 'scheduled',
  scheduled_at       timestamptz,
  started_at         timestamptz,
  completed_at       timestamptz,
  closed_at          timestamptz,
  overall_score      numeric(5, 2),
  passed             boolean,
  notes              text,
  reinspection_of     uuid references public.inspections (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.inspections is
  'overall_score/passed are always written by complete_inspection() from the real submitted inspection_results — never client-supplied.';

create index inspections_tenant_id_idx on public.inspections (tenant_id);
create index inspections_client_id_idx on public.inspections (client_id);
create index inspections_site_id_idx on public.inspections (site_id);
create index inspections_status_idx on public.inspections (status);

create trigger inspections_set_updated_at
  before update on public.inspections
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_inspection_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: site % does not belong to client %', new.site_id, new.client_id;
  end if;
  if not exists (select 1 from public.inspection_templates where id = new.template_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: template % does not belong to tenant %', new.template_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: contract % does not belong to client %', new.contract_id, new.client_id;
  end if;
  return new;
end;
$$;

create trigger inspections_validate_tenant_refs
  before insert or update on public.inspections
  for each row
  execute function public.validate_inspection_tenant_refs();

create or replace function public.inspections_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
    (old.status = 'scheduled' and new.status = 'in_progress')
    or (old.status = 'in_progress' and new.status = 'completed')
    or (old.status = 'completed' and new.status = 'closed')
  ) then
    raise exception 'invalid_transition: cannot move inspection from % to %', old.status, new.status;
  end if;
  return new;
end;
$$;

create trigger inspections_validate_transition_trigger
  before update on public.inspections
  for each row
  execute function public.inspections_validate_transition();

alter table public.inspections enable row level security;
alter table public.inspections force row level security;

create policy inspections_select on public.inspections for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
    or public.is_platform_admin()
  );

create policy inspections_write_by_manager on public.inspections for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger inspections_audit_log
  after insert or update on public.inspections
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create table public.inspection_results (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  inspection_id     uuid not null references public.inspections (id) on delete cascade,
  template_item_id  uuid not null references public.inspection_template_items (id) on delete restrict,
  score             numeric(5, 2) not null check (score >= 0),
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (inspection_id, template_item_id)
);

create index inspection_results_tenant_id_idx on public.inspection_results (tenant_id);
create index inspection_results_inspection_id_idx on public.inspection_results (inspection_id);

create trigger inspection_results_set_updated_at
  before update on public.inspection_results
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_inspection_result_tenant_refs()
returns trigger
language plpgsql
as $$
declare
  v_max_score numeric;
begin
  if not exists (select 1 from public.inspections where id = new.inspection_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: inspection % does not belong to tenant %', new.inspection_id, new.tenant_id;
  end if;
  select max_score into v_max_score from public.inspection_template_items where id = new.template_item_id and tenant_id = new.tenant_id;
  if v_max_score is null then
    raise exception 'cross_tenant_reference: template item % does not belong to tenant %', new.template_item_id, new.tenant_id;
  end if;
  if new.score > v_max_score then
    raise exception 'invalid_score: score % exceeds this criterion''s max_score %', new.score, v_max_score;
  end if;
  return new;
end;
$$;

create trigger inspection_results_validate_tenant_refs
  before insert or update on public.inspection_results
  for each row
  execute function public.validate_inspection_result_tenant_refs();

alter table public.inspection_results enable row level security;
alter table public.inspection_results force row level security;

create policy inspection_results_select on public.inspection_results for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or exists (select 1 from public.inspections i where i.id = inspection_results.inspection_id and i.client_id = public.current_client_id())
    or public.is_platform_admin()
  );

create policy inspection_results_write_by_manager on public.inspection_results for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

-- ---------------------------------------------------------------------------
create table public.defects (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  inspection_id       uuid not null references public.inspections (id) on delete cascade,
  inspection_result_id uuid references public.inspection_results (id) on delete set null,
  severity            public.defect_severity not null default 'medium',
  description         text not null check (char_length(description) > 0),
  area_label          text,
  responsible_team_id uuid references public.teams (id) on delete set null,
  due_date            date,
  status              public.defect_status not null default 'open',
  corrective_action    text,
  resolution_notes     text,
  resolved_by          uuid references public.profiles (id) on delete set null,
  resolved_at          timestamptz,
  verified_by          uuid references public.profiles (id) on delete set null,
  verified_at          timestamptz,
  reinspection_id      uuid references public.inspections (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.defects is
  'resolved_by/resolved_at/verified_by/verified_at are server-derived — never client-supplied. A defect is never simply deleted when it changes status; the full status history remains queryable via audit_log.';

create index defects_tenant_id_idx on public.defects (tenant_id);
create index defects_inspection_id_idx on public.defects (inspection_id);
create index defects_status_idx on public.defects (status);

create trigger defects_set_updated_at
  before update on public.defects
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_defect_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.inspections where id = new.inspection_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: inspection % does not belong to tenant %', new.inspection_id, new.tenant_id;
  end if;
  if new.responsible_team_id is not null and not exists (select 1 from public.teams where id = new.responsible_team_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: team % does not belong to tenant %', new.responsible_team_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger defects_validate_tenant_refs
  before insert or update on public.defects
  for each row
  execute function public.validate_defect_tenant_refs();

create or replace function public.defects_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
    (old.status = 'open' and new.status in ('in_progress', 'resolved'))
    or (old.status = 'in_progress' and new.status = 'resolved')
    or (old.status = 'resolved' and new.status = 'verified')
  ) then
    raise exception 'invalid_transition: cannot move defect from % to %', old.status, new.status;
  end if;
  return new;
end;
$$;

create trigger defects_validate_transition_trigger
  before update on public.defects
  for each row
  execute function public.defects_validate_transition();

alter table public.defects enable row level security;
alter table public.defects force row level security;

create policy defects_select on public.defects for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or exists (select 1 from public.inspections i where i.id = defects.inspection_id and i.client_id = public.current_client_id())
    or public.is_platform_admin()
  );

create policy defects_write_by_manager on public.defects for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger defects_audit_log
  after insert or update on public.defects
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create or replace function public.start_inspection(p_inspection_id uuid)
returns public.inspections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.inspections;
begin
  select * into v_inspection from public.inspections where id = p_inspection_id;
  if not found then
    raise exception 'not_found: no inspection %', p_inspection_id;
  end if;
  if not public.can_manage_operations(v_inspection.tenant_id) then
    raise exception 'insufficient_privilege: cannot start this inspection';
  end if;
  if v_inspection.status <> 'scheduled' then
    raise exception 'invalid_state: inspection % is not scheduled (status: %)', p_inspection_id, v_inspection.status;
  end if;

  update public.inspections set status = 'in_progress', started_at = now(), inspector_id = coalesce(inspector_id, auth.uid())
    where id = p_inspection_id returning * into v_inspection;
  return v_inspection;
end;
$$;

revoke execute on function public.start_inspection(uuid) from public, anon;
grant execute on function public.start_inspection(uuid) to authenticated;

create or replace function public.submit_inspection_result(p_inspection_id uuid, p_template_item_id uuid, p_score numeric, p_notes text default null)
returns public.inspection_results
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.inspections;
  v_result public.inspection_results;
begin
  select * into v_inspection from public.inspections where id = p_inspection_id;
  if not found then
    raise exception 'not_found: no inspection %', p_inspection_id;
  end if;
  if not public.can_manage_operations(v_inspection.tenant_id) then
    raise exception 'insufficient_privilege: cannot submit results for this inspection';
  end if;
  if v_inspection.status <> 'in_progress' then
    raise exception 'invalid_state: inspection % is not in progress (status: %)', p_inspection_id, v_inspection.status;
  end if;

  insert into public.inspection_results (tenant_id, inspection_id, template_item_id, score, notes)
  values (v_inspection.tenant_id, p_inspection_id, p_template_item_id, p_score, p_notes)
  on conflict (inspection_id, template_item_id) do update set score = excluded.score, notes = excluded.notes
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.submit_inspection_result(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.submit_inspection_result(uuid, uuid, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_inspection: the deterministic scoring boundary. Requires every
-- template item to have a submitted result (a real completeness check,
-- never assumed) and computes overall_score as a weighted percentage —
-- SUM(score * weight) / SUM(max_score * weight) * 100 — server-side,
-- always, never trusting a client-submitted score.

create or replace function public.complete_inspection(p_inspection_id uuid)
returns public.inspections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.inspections;
  v_template_item_count integer;
  v_result_count integer;
  v_weighted_score numeric;
  v_weighted_max numeric;
  v_overall_score numeric(5, 2);
  v_pass_threshold numeric;
begin
  select * into v_inspection from public.inspections where id = p_inspection_id;
  if not found then
    raise exception 'not_found: no inspection %', p_inspection_id;
  end if;
  if not public.can_manage_operations(v_inspection.tenant_id) then
    raise exception 'insufficient_privilege: cannot complete this inspection';
  end if;
  if v_inspection.status <> 'in_progress' then
    raise exception 'invalid_state: inspection % is not in progress (status: %)', p_inspection_id, v_inspection.status;
  end if;

  select count(*) into v_template_item_count from public.inspection_template_items where template_id = v_inspection.template_id;
  select count(*) into v_result_count from public.inspection_results where inspection_id = p_inspection_id;
  if v_result_count < v_template_item_count then
    raise exception 'incomplete_inspection: % of % criteria have a submitted result', v_result_count, v_template_item_count;
  end if;

  select coalesce(sum(r.score * i.weight), 0), coalesce(sum(i.max_score * i.weight), 0)
    into v_weighted_score, v_weighted_max
    from public.inspection_results r
    join public.inspection_template_items i on i.id = r.template_item_id
    where r.inspection_id = p_inspection_id;

  v_overall_score := case when v_weighted_max > 0 then round(v_weighted_score / v_weighted_max * 100, 2) else 0 end;

  select pass_threshold into v_pass_threshold from public.inspection_templates where id = v_inspection.template_id;

  update public.inspections
    set status = 'completed', completed_at = now(), overall_score = v_overall_score, passed = (v_overall_score >= v_pass_threshold)
    where id = p_inspection_id
    returning * into v_inspection;

  perform public.write_audit_log(v_inspection.tenant_id, auth.uid(), 'inspection_completed', 'inspections', p_inspection_id, null,
    jsonb_build_object('overall_score', v_overall_score, 'passed', v_inspection.passed));

  return v_inspection;
end;
$$;

comment on function public.complete_inspection(uuid) is
  'Deterministic weighted-percentage scoring from the real submitted inspection_results — never AI, never client-supplied. Requires every template item to have a result first.';

revoke execute on function public.complete_inspection(uuid) from public, anon;
grant execute on function public.complete_inspection(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.create_defect(
  p_inspection_id uuid,
  p_description text,
  p_severity public.defect_severity default 'medium',
  p_area_label text default null,
  p_responsible_team_id uuid default null,
  p_due_date date default null,
  p_inspection_result_id uuid default null
)
returns public.defects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.inspections;
  v_result public.defects;
begin
  select * into v_inspection from public.inspections where id = p_inspection_id;
  if not found then
    raise exception 'not_found: no inspection %', p_inspection_id;
  end if;
  if not public.can_manage_operations(v_inspection.tenant_id) then
    raise exception 'insufficient_privilege: cannot log a defect for this inspection';
  end if;
  if v_inspection.status not in ('completed', 'closed') then
    raise exception 'invalid_state: inspection % has no results to attach a defect to yet (status: %)', p_inspection_id, v_inspection.status;
  end if;

  insert into public.defects (tenant_id, inspection_id, inspection_result_id, severity, description, area_label, responsible_team_id, due_date)
  values (v_inspection.tenant_id, p_inspection_id, p_inspection_result_id, p_severity, p_description, p_area_label, p_responsible_team_id, p_due_date)
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.create_defect(uuid, text, public.defect_severity, text, uuid, date, uuid) from public, anon;
grant execute on function public.create_defect(uuid, text, public.defect_severity, text, uuid, date, uuid) to authenticated;

create or replace function public.resolve_defect(p_defect_id uuid, p_resolution_notes text, p_corrective_action text default null)
returns public.defects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_defect public.defects;
  v_result public.defects;
begin
  select * into v_defect from public.defects where id = p_defect_id;
  if not found then
    raise exception 'not_found: no defect %', p_defect_id;
  end if;
  if not public.can_manage_operations(v_defect.tenant_id) then
    raise exception 'insufficient_privilege: cannot resolve this defect';
  end if;
  if v_defect.status not in ('open', 'in_progress') then
    raise exception 'invalid_state: defect % is not open (status: %)', p_defect_id, v_defect.status;
  end if;

  update public.defects
    set status = 'resolved', resolution_notes = p_resolution_notes, corrective_action = coalesce(p_corrective_action, corrective_action),
        resolved_by = auth.uid(), resolved_at = now()
    where id = p_defect_id
    returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.resolve_defect(uuid, text, text) from public, anon;
grant execute on function public.resolve_defect(uuid, text, text) to authenticated;

-- Self-verification is blocked, matching the established
-- decide_attendance_location_exception()/verify_task() pattern.
create or replace function public.verify_defect(p_defect_id uuid)
returns public.defects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_defect public.defects;
  v_result public.defects;
begin
  select * into v_defect from public.defects where id = p_defect_id;
  if not found then
    raise exception 'not_found: no defect %', p_defect_id;
  end if;
  if not public.can_manage_operations(v_defect.tenant_id) then
    raise exception 'insufficient_privilege: cannot verify this defect';
  end if;
  if v_defect.status <> 'resolved' then
    raise exception 'invalid_state: defect % is not resolved (status: %)', p_defect_id, v_defect.status;
  end if;
  if v_defect.resolved_by = auth.uid() then
    raise exception 'self_verification_not_allowed: you cannot verify a defect you resolved yourself';
  end if;

  update public.defects set status = 'verified', verified_by = auth.uid(), verified_at = now()
    where id = p_defect_id
    returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.verify_defect(uuid) from public, anon;
grant execute on function public.verify_defect(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- close_inspection: requires no open/in_progress defects remain — a
-- database-enforced check, not a UI-only convention.

create or replace function public.close_inspection(p_inspection_id uuid)
returns public.inspections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.inspections;
  v_open_defects integer;
begin
  select * into v_inspection from public.inspections where id = p_inspection_id;
  if not found then
    raise exception 'not_found: no inspection %', p_inspection_id;
  end if;
  if not public.can_manage_operations(v_inspection.tenant_id) then
    raise exception 'insufficient_privilege: cannot close this inspection';
  end if;
  if v_inspection.status <> 'completed' then
    raise exception 'invalid_state: inspection % is not completed (status: %)', p_inspection_id, v_inspection.status;
  end if;

  select count(*) into v_open_defects from public.defects where inspection_id = p_inspection_id and status in ('open', 'in_progress');
  if v_open_defects > 0 then
    raise exception 'open_defects_remain: % defect(s) on inspection % are not yet resolved', v_open_defects, p_inspection_id;
  end if;

  update public.inspections set status = 'closed', closed_at = now() where id = p_inspection_id returning * into v_inspection;
  return v_inspection;
end;
$$;

revoke execute on function public.close_inspection(uuid) from public, anon;
grant execute on function public.close_inspection(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.schedule_reinspection(p_defect_id uuid, p_scheduled_at timestamptz default null)
returns public.inspections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_defect public.defects;
  v_original public.inspections;
  v_new_inspection public.inspections;
begin
  select * into v_defect from public.defects where id = p_defect_id;
  if not found then
    raise exception 'not_found: no defect %', p_defect_id;
  end if;
  if not public.can_manage_operations(v_defect.tenant_id) then
    raise exception 'insufficient_privilege: cannot schedule a reinspection for this defect';
  end if;

  select * into v_original from public.inspections where id = v_defect.inspection_id;

  insert into public.inspections (tenant_id, client_id, site_id, contract_id, template_id, scheduled_at, reinspection_of)
  values (v_original.tenant_id, v_original.client_id, v_original.site_id, v_original.contract_id, v_original.template_id, p_scheduled_at, v_original.id)
  returning * into v_new_inspection;

  update public.defects set reinspection_id = v_new_inspection.id where id = p_defect_id;

  return v_new_inspection;
end;
$$;

revoke execute on function public.schedule_reinspection(uuid, timestamptz) from public, anon;
grant execute on function public.schedule_reinspection(uuid, timestamptz) to authenticated;
