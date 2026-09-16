-- Sebetsa Phase S — Site Survey.
--
-- The front of the commercial chain: PROSPECTIVE CLIENT -> SITE SURVEY ->
-- SCOPE OF WORK -> QUOTE. A survey captures what a salesperson/manager
-- observes about a prospective (or existing) site from a phone/tablet, and
-- can be converted into a real `sites` row once the client is won — never
-- inventing scope-of-work items from survey counts (that would be
-- fabricated business logic guessing at cleaning requirements); the real
-- Scope of Work engine (Phase Q) already exists for a manager to author
-- that deliberately, informed by the survey's own notes.
--
-- Photo capture is intentionally deferred from this pass (noted, not
-- silently dropped) — it would reuse the existing private-bucket +
-- metadata-table pattern (contract_documents/employee_documents) with no
-- schema change needed here, but is a second, separate piece of work.

create type public.site_survey_status as enum ('draft', 'completed', 'converted');

create table public.site_surveys (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.organizations (id) on delete cascade,
  client_id               uuid not null references public.clients (id) on delete cascade,
  site_id                 uuid references public.sites (id) on delete set null,
  conducted_by            uuid references public.profiles (id) on delete set null,
  status                  public.site_survey_status not null default 'draft',
  prospective_site_name   text not null check (char_length(prospective_site_name) > 0),
  address                 text,
  building_type           text,
  floor_count             integer check (floor_count is null or floor_count >= 0),
  approx_area_sqm         numeric(10, 2) check (approx_area_sqm is null or approx_area_sqm >= 0),
  office_count            integer check (office_count is null or office_count >= 0),
  bathroom_count          integer check (bathroom_count is null or bathroom_count >= 0),
  kitchen_count           integer check (kitchen_count is null or kitchen_count >= 0),
  entrance_count          integer check (entrance_count is null or entrance_count >= 0),
  common_area_count       integer check (common_area_count is null or common_area_count >= 0),
  window_count            integer check (window_count is null or window_count >= 0),
  floor_types             text,
  special_surfaces        text,
  operating_hours         text,
  access_restrictions     text,
  required_services       text,
  equipment_requirements  text,
  consumable_requirements text,
  risks                   text,
  special_instructions    text,
  notes                   text,
  conducted_at            timestamptz not null default now(),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.site_surveys is
  'A field survey of a prospective (or existing) site. Converts into a real `sites` row via convert_site_survey_to_site() — never auto-generates scope-of-work items from its counts, which would be fabricated business logic.';

create index site_surveys_tenant_id_idx on public.site_surveys (tenant_id);
create index site_surveys_client_id_idx on public.site_surveys (client_id);
create index site_surveys_site_id_idx on public.site_surveys (site_id);

create trigger site_surveys_set_updated_at
  before update on public.site_surveys
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_site_survey_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger site_surveys_validate_tenant_refs
  before insert or update on public.site_surveys
  for each row
  execute function public.validate_site_survey_tenant_refs();

alter table public.site_surveys enable row level security;
alter table public.site_surveys force row level security;

create policy site_surveys_select_within_tenant on public.site_surveys for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy site_surveys_write_by_manager on public.site_surveys for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger site_surveys_audit_log
  after insert or update on public.site_surveys
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- convert_site_survey_to_site: the real, honest half of SITE SURVEY -> SITE
-- -> SCOPE. Creates a real `sites` row from the survey's own captured
-- data, links the survey to it, and flips status to 'converted' — exactly
-- once (a survey cannot be converted twice, and cannot convert if it
-- already has a site_id).

create or replace function public.convert_site_survey_to_site(p_survey_id uuid)
returns public.sites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_survey public.site_surveys;
  v_site public.sites;
begin
  select * into v_survey from public.site_surveys where id = p_survey_id;
  if not found then
    raise exception 'not_found: no site survey %', p_survey_id;
  end if;

  if not public.can_manage_org_structure(v_survey.tenant_id) then
    raise exception 'insufficient_privilege: cannot convert this survey';
  end if;

  if v_survey.site_id is not null then
    raise exception 'already_converted: survey % was already converted to site %', p_survey_id, v_survey.site_id;
  end if;

  insert into public.sites (tenant_id, client_id, name, address, site_type, status)
  values (v_survey.tenant_id, v_survey.client_id, v_survey.prospective_site_name, v_survey.address, v_survey.building_type, 'onboarding')
  returning * into v_site;

  update public.site_surveys set site_id = v_site.id, status = 'converted' where id = p_survey_id;

  perform public.write_audit_log(v_survey.tenant_id, auth.uid(), 'site_survey_converted_to_site', 'site_surveys', v_survey.id, null,
    jsonb_build_object('site_id', v_site.id));

  return v_site;
end;
$$;

comment on function public.convert_site_survey_to_site(uuid) is
  'The controlled SITE SURVEY -> SITE boundary: creates a real sites row from the survey''s own captured name/address/building_type, exactly once. The manager then adds site_areas/scope_of_work_items deliberately — never auto-generated from survey counts.';

revoke execute on function public.convert_site_survey_to_site(uuid) from public, anon;
grant execute on function public.convert_site_survey_to_site(uuid) to authenticated;
