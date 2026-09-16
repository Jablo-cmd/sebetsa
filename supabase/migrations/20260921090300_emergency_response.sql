-- Sebetsa Domain 14 (part 2) — Panic / duress / emergency response.
--
-- Treated as safety-critical, not a boolean flag: the trigger itself is an
-- immutable event record (emergency_events, insert-only — the fact that a
-- panic was triggered, when, where, by whom, can never be edited away),
-- with a separate mutable lifecycle row (emergency_responses) tracking
-- what the organisation did about it. Location on the event is visible
-- only to the operations-management tier — never a blanket tenant-wide
-- read, and never to client_user under any circumstance.

create type public.emergency_type as enum ('panic', 'medical', 'security_threat', 'other');
create type public.emergency_status as enum ('triggered', 'acknowledged', 'responding', 'resolved');

-- ---------------------------------------------------------------------------
-- 14B.1 The trigger event — immutable.

create table public.emergency_events (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.organizations (id) on delete cascade,
  employee_id     uuid not null references public.employees (id) on delete cascade,
  site_id         uuid references public.sites (id) on delete set null,
  shift_id        uuid references public.shifts (id) on delete set null,
  emergency_type  public.emergency_type not null default 'panic',
  latitude        numeric(9, 6) check (latitude is null or latitude between -90 and 90),
  longitude       numeric(9, 6) check (longitude is null or longitude between -180 and 180),
  accuracy_meters numeric(8, 2) check (accuracy_meters is null or accuracy_meters >= 0),
  triggered_at    timestamptz not null default now(),
  device_context  jsonb not null default '{}'::jsonb
);

comment on table public.emergency_events is
  'Append-only — no UPDATE/DELETE policy for authenticated, ever. The immutable fact that an emergency was triggered. See emergency_responses for the mutable lifecycle that follows it.';

create index emergency_events_tenant_id_idx on public.emergency_events (tenant_id, triggered_at);
create index emergency_events_employee_id_idx on public.emergency_events (employee_id);

create or replace function public.validate_emergency_event_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.shift_id is not null and not exists (select 1 from public.shifts where id = new.shift_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: shift % does not belong to tenant %', new.shift_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger emergency_events_validate_tenant_refs
  before insert on public.emergency_events
  for each row
  execute function public.validate_emergency_event_tenant_refs();

alter table public.emergency_events enable row level security;
alter table public.emergency_events force row level security;

-- Location + identity is the most sensitive data this domain touches —
-- restricted to the operations-management tier and the triggering
-- employee's own event, never a blanket tenant-wide read, never
-- client_user (can_manage_operations already excludes it).
create policy emergency_events_select on public.emergency_events for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = emergency_events.employee_id and e.profile_id = auth.uid())
  );

-- No direct client write policy — trigger_emergency() RPC only.

-- ---------------------------------------------------------------------------
-- 14B.2 Emergency lifecycle — one mutable row per event.

create table public.emergency_responses (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  emergency_event_id  uuid not null references public.emergency_events (id) on delete cascade,
  status              public.emergency_status not null default 'triggered',
  acknowledged_by     uuid references public.profiles (id) on delete set null,
  acknowledged_at     timestamptz,
  responding_by       uuid references public.profiles (id) on delete set null,
  responding_at       timestamptz,
  resolved_by         uuid references public.profiles (id) on delete set null,
  resolved_at         timestamptz,
  resolution_reason   text,
  escalation_level    integer not null default 0,
  last_escalated_at   timestamptz,
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (emergency_event_id)
);

create index emergency_responses_tenant_status_idx on public.emergency_responses (tenant_id, status);

create trigger emergency_responses_set_updated_at
  before update on public.emergency_responses
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_emergency_response_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.emergency_events where id = new.emergency_event_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: emergency event % does not belong to tenant %', new.emergency_event_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger emergency_responses_validate_tenant_refs
  before insert or update on public.emergency_responses
  for each row
  execute function public.validate_emergency_response_tenant_refs();

alter table public.emergency_responses enable row level security;
alter table public.emergency_responses force row level security;

create policy emergency_responses_select on public.emergency_responses for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.emergency_events ee join public.employees e on e.id = ee.employee_id
      where ee.id = emergency_responses.emergency_event_id and e.profile_id = auth.uid()
    )
  );

-- No direct client write policy — trigger/acknowledge/respond/resolve RPCs only.

-- ---------------------------------------------------------------------------
-- 14B.4 Tenant-configurable escalation policy — an ordered chain, not a
-- single hard-coded org-wide path.

create table public.emergency_escalation_policies (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  level             integer not null check (level > 0),
  escalate_to_role  public.user_role not null,
  timeout_minutes   integer not null check (timeout_minutes > 0),
  created_at        timestamptz not null default now(),
  unique (tenant_id, level)
);

comment on table public.emergency_escalation_policies is
  'Ordered per-tenant escalation chain: if level N''s role has not acknowledged within timeout_minutes, escalate_emergency_if_overdue() notifies level N+1. No org-wide hard-coded chain — every tenant configures its own (or none at all, which just means no auto-escalation runs for that tenant).';

create index emergency_escalation_policies_tenant_idx on public.emergency_escalation_policies (tenant_id, level);

alter table public.emergency_escalation_policies enable row level security;
alter table public.emergency_escalation_policies force row level security;

create policy emergency_escalation_policies_select on public.emergency_escalation_policies for select to authenticated
  using (public.can_manage_operations(tenant_id));

create policy emergency_escalation_policies_write on public.emergency_escalation_policies for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- ---------------------------------------------------------------------------
-- 14B.1/14B.2/14B.4 RPCs.

create or replace function public.trigger_emergency(
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_accuracy_meters numeric default null,
  p_emergency_type public.emergency_type default 'panic',
  p_site_id uuid default null,
  p_device_context jsonb default '{}'::jsonb
)
returns public.emergency_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employees;
  v_shift_id uuid;
  v_event public.emergency_events;
  v_response public.emergency_responses;
begin
  select * into v_employee from public.employees where profile_id = auth.uid();
  if not found then
    raise exception 'not_found: no employee record linked to your account';
  end if;

  select id into v_shift_id from public.shifts
    where employee_id = v_employee.id and starts_at <= now() and ends_at >= now()
    order by starts_at desc limit 1;

  insert into public.emergency_events (tenant_id, employee_id, site_id, shift_id, emergency_type, latitude, longitude, accuracy_meters, device_context)
  values (v_employee.tenant_id, v_employee.id, coalesce(p_site_id, v_employee.home_site_id), v_shift_id, p_emergency_type, p_latitude, p_longitude, p_accuracy_meters, coalesce(p_device_context, '{}'::jsonb))
  returning * into v_event;

  insert into public.emergency_responses (tenant_id, emergency_event_id, status)
  values (v_employee.tenant_id, v_event.id, 'triggered')
  returning * into v_response;

  insert into public.operational_alerts (tenant_id, alert_type, severity, site_id, employee_id, message)
  values (v_employee.tenant_id, 'emergency_active', 'critical', v_event.site_id, v_employee.id,
    format('EMERGENCY: %s triggered by %s %s', p_emergency_type, v_employee.first_name, v_employee.last_name));

  -- Not logged with the raw employee identity in the audit action name —
  -- the entity_id/entity_table link is enough for anyone with legitimate
  -- audit_log access to trace it, and audit_log carries its own RLS.
  perform public.write_audit_log(v_employee.tenant_id, auth.uid(), 'emergency_triggered', 'emergency_events', v_event.id, null,
    jsonb_build_object('emergency_type', p_emergency_type, 'site_id', v_event.site_id));

  return v_event;
end;
$$;

revoke execute on function public.trigger_emergency(numeric, numeric, numeric, public.emergency_type, uuid, jsonb) from public, anon;
grant execute on function public.trigger_emergency(numeric, numeric, numeric, public.emergency_type, uuid, jsonb) to authenticated;

create or replace function public.acknowledge_emergency(p_emergency_event_id uuid)
returns public.emergency_responses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.emergency_events;
  v_response public.emergency_responses;
  v_result public.emergency_responses;
begin
  select * into v_event from public.emergency_events where id = p_emergency_event_id;
  if not found then
    raise exception 'not_found: no emergency event %', p_emergency_event_id;
  end if;
  if not public.can_manage_operations(v_event.tenant_id) then
    raise exception 'insufficient_privilege: cannot acknowledge emergencies for this tenant';
  end if;
  if exists (select 1 from public.employees where id = v_event.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot acknowledge your own emergency — independent response oversight is required';
  end if;

  select * into v_response from public.emergency_responses where emergency_event_id = p_emergency_event_id for update;
  if v_response.status <> 'triggered' then
    raise exception 'invalid_transition: only a triggered emergency can be acknowledged (current status: %)', v_response.status;
  end if;

  update public.emergency_responses set status = 'acknowledged', acknowledged_by = auth.uid(), acknowledged_at = now()
    where emergency_event_id = p_emergency_event_id returning * into v_result;

  perform public.write_audit_log(v_event.tenant_id, auth.uid(), 'emergency_acknowledged', 'emergency_events', p_emergency_event_id, jsonb_build_object('status', 'triggered'), jsonb_build_object('status', 'acknowledged'));
  return v_result;
end;
$$;

revoke execute on function public.acknowledge_emergency(uuid) from public, anon;
grant execute on function public.acknowledge_emergency(uuid) to authenticated;

create or replace function public.respond_to_emergency(p_emergency_event_id uuid, p_notes text default null)
returns public.emergency_responses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.emergency_events;
  v_response public.emergency_responses;
  v_result public.emergency_responses;
begin
  select * into v_event from public.emergency_events where id = p_emergency_event_id;
  if not found then
    raise exception 'not_found: no emergency event %', p_emergency_event_id;
  end if;
  if not public.can_manage_operations(v_event.tenant_id) then
    raise exception 'insufficient_privilege: cannot respond to emergencies for this tenant';
  end if;
  if exists (select 1 from public.employees where id = v_event.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot respond to your own emergency — independent response oversight is required';
  end if;

  select * into v_response from public.emergency_responses where emergency_event_id = p_emergency_event_id for update;
  if v_response.status not in ('acknowledged', 'responding') then
    raise exception 'invalid_transition: emergency must be acknowledged before responding (current status: %)', v_response.status;
  end if;

  update public.emergency_responses
    set status = 'responding', responding_by = auth.uid(), responding_at = now(),
        notes = case when p_notes is not null then coalesce(notes || E'\n', '') || p_notes else notes end
    where emergency_event_id = p_emergency_event_id returning * into v_result;

  perform public.write_audit_log(v_event.tenant_id, auth.uid(), 'emergency_responding', 'emergency_events', p_emergency_event_id, jsonb_build_object('status', v_response.status), jsonb_build_object('status', 'responding'));
  return v_result;
end;
$$;

revoke execute on function public.respond_to_emergency(uuid, text) from public, anon;
grant execute on function public.respond_to_emergency(uuid, text) to authenticated;

create or replace function public.resolve_emergency(p_emergency_event_id uuid, p_resolution_reason text)
returns public.emergency_responses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.emergency_events;
  v_response public.emergency_responses;
  v_result public.emergency_responses;
begin
  select * into v_event from public.emergency_events where id = p_emergency_event_id;
  if not found then
    raise exception 'not_found: no emergency event %', p_emergency_event_id;
  end if;
  if not public.can_manage_operations(v_event.tenant_id) then
    raise exception 'insufficient_privilege: cannot resolve emergencies for this tenant';
  end if;
  if exists (select 1 from public.employees where id = v_event.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot resolve your own emergency — independent response oversight is required';
  end if;

  select * into v_response from public.emergency_responses where emergency_event_id = p_emergency_event_id for update;
  if v_response.status = 'resolved' then
    raise exception 'invalid_transition: emergency is already resolved';
  end if;
  if v_response.status = 'triggered' then
    raise exception 'invalid_transition: an unacknowledged emergency cannot be resolved directly — acknowledge it first';
  end if;

  update public.emergency_responses set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_reason = p_resolution_reason
    where emergency_event_id = p_emergency_event_id returning * into v_result;

  update public.operational_alerts set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_notes = p_resolution_reason
    where tenant_id = v_event.tenant_id and alert_type = 'emergency_active' and employee_id = v_event.employee_id and status <> 'resolved';

  perform public.write_audit_log(v_event.tenant_id, auth.uid(), 'emergency_resolved', 'emergency_events', p_emergency_event_id, jsonb_build_object('status', v_response.status), jsonb_build_object('status', 'resolved', 'resolution_reason', p_resolution_reason));
  return v_result;
end;
$$;

revoke execute on function public.resolve_emergency(uuid, text) from public, anon;
grant execute on function public.resolve_emergency(uuid, text) to authenticated;

-- Escalation sweep: cron-only, same posture as the alert sweeps. Advances
-- escalation_level for any triggered-and-unacknowledged emergency whose
-- current level has timed out, per the tenant's own configured chain.
create or replace function public.escalate_overdue_emergencies()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
  v_next_policy public.emergency_escalation_policies;
begin
  for v_row in
    select er.id as response_id, er.tenant_id, er.emergency_event_id, er.escalation_level, ee.triggered_at
    from public.emergency_responses er
    join public.emergency_events ee on ee.id = er.emergency_event_id
    where er.status = 'triggered'
  loop
    select * into v_next_policy from public.emergency_escalation_policies
      where tenant_id = v_row.tenant_id and level = v_row.escalation_level + 1;
    if not found then
      continue;
    end if;

    if now() >= coalesce(v_row.triggered_at, now()) + make_interval(mins => v_next_policy.timeout_minutes) * (v_row.escalation_level + 1) then
      update public.emergency_responses set escalation_level = v_next_policy.level, last_escalated_at = now() where id = v_row.response_id;
      perform public.write_audit_log(v_row.tenant_id, null, 'emergency_escalated', 'emergency_events', v_row.emergency_event_id, jsonb_build_object('escalation_level', v_row.escalation_level), jsonb_build_object('escalation_level', v_next_policy.level, 'escalated_to_role', v_next_policy.escalate_to_role));
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.escalate_overdue_emergencies() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('sebetsa-emergency-escalation-sweep', '* * * * *', $sql$select public.escalate_overdue_emergencies();$sql$);
  else
    raise notice 'pg_cron extension not available in this environment — escalate_overdue_emergencies() created, but not scheduled. Enable pg_cron on the hosted Supabase project and re-run this migration''s DO block.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 14.1/14.2 Command Centre snapshot (deferred here from the previous
-- migration — see its own trailing comment). SECURITY INVOKER, RLS-riding,
-- same design as get_operational_metrics(): no explicit role check of its
-- own, every figure a live aggregate over tables whose RLS already governs
-- who sees what.

create or replace function public.get_command_centre_snapshot(p_tenant_id uuid)
returns table (
  workforce_total_scheduled bigint,
  workforce_clocked_in bigint,
  workforce_absent bigint,
  workforce_late bigint,
  workforce_pending_exceptions bigint,
  sites_total_active bigint,
  sites_understaffed bigint,
  sites_uncovered bigint,
  patrols_active bigint,
  patrols_completed_today bigint,
  patrols_missed bigint,
  compliance_expired bigint,
  compliance_expiring_soon bigint,
  incidents_open bigint,
  incidents_critical bigint,
  incidents_overdue bigint,
  tasks_overdue bigint,
  tasks_verification_pending bigint,
  contracts_active bigint,
  contracts_sla_breaching bigint,
  emergencies_active bigint,
  alerts_open bigint,
  alerts_critical bigint
)
language sql
stable
as $$
  select
    (select count(*) from public.shifts where tenant_id = p_tenant_id and starts_at::date = current_date),
    (select count(*) from public.attendance_records where tenant_id = p_tenant_id and clock_in_at is not null and clock_out_at is null),
    (select count(*) from public.shifts sh
       where sh.tenant_id = p_tenant_id and sh.starts_at::date = current_date and sh.starts_at < now() - interval '30 minutes'
         and not exists (select 1 from public.attendance_records ar where ar.shift_id = sh.id and ar.clock_in_at is not null)),
    (select count(*) from public.attendance_records where tenant_id = p_tenant_id and status = 'late' and created_at::date = current_date),
    (select count(*) from public.attendance_location_exceptions where tenant_id = p_tenant_id and status = 'pending'),

    (select count(*) from public.sites where tenant_id = p_tenant_id and status = 'active'),
    (select count(*) from (
       select ssr.site_id from public.site_staffing_requirements ssr
       left join public.site_assignments sa on sa.site_id = ssr.site_id and (sa.end_date is null or sa.end_date >= current_date)
       where ssr.tenant_id = p_tenant_id
       group by ssr.site_id having count(distinct sa.employee_id) < sum(ssr.required_count)
     ) understaffed),
    (select count(*) from public.sites s where s.tenant_id = p_tenant_id and s.status = 'active'
       and not exists (select 1 from public.site_assignments sa where sa.site_id = s.id and (sa.end_date is null or sa.end_date >= current_date))),

    (select count(*) from public.patrol_runs where tenant_id = p_tenant_id and status = 'in_progress'),
    (select count(*) from public.patrol_runs where tenant_id = p_tenant_id and status = 'completed' and completed_at::date = current_date),
    (select count(*) from public.operational_alerts where tenant_id = p_tenant_id and alert_type = 'patrol_missed' and status <> 'resolved'),

    (select count(*) from public.compliance_records where tenant_id = p_tenant_id and status = 'expired'),
    (select count(*) from public.compliance_records where tenant_id = p_tenant_id and status = 'compliant' and expiry_date is not null and expiry_date between current_date and current_date + 30),

    (select count(*) from public.incidents where tenant_id = p_tenant_id and status <> 'closed'),
    (select count(*) from public.incidents where tenant_id = p_tenant_id and severity = 'critical' and status <> 'closed'),
    (select count(*) from public.operational_alerts where tenant_id = p_tenant_id and alert_type = 'incident_overdue' and status <> 'resolved'),

    (select count(*) from public.tasks where tenant_id = p_tenant_id and status in ('open', 'in_progress') and due_at is not null and due_at < now()),
    (select count(*) from public.tasks where tenant_id = p_tenant_id and status = 'completed'),

    (select count(*) from public.contracts where tenant_id = p_tenant_id and status = 'active'),
    (select count(*) from public.operational_alerts where tenant_id = p_tenant_id and alert_type = 'contract_sla_breach' and status <> 'resolved'),

    (select count(*) from public.emergency_responses er join public.emergency_events ee on ee.id = er.emergency_event_id where ee.tenant_id = p_tenant_id and er.status <> 'resolved'),

    (select count(*) from public.operational_alerts where tenant_id = p_tenant_id and status = 'open'),
    (select count(*) from public.operational_alerts where tenant_id = p_tenant_id and status = 'open' and severity = 'critical')
$$;

revoke execute on function public.get_command_centre_snapshot(uuid) from public, anon;
grant execute on function public.get_command_centre_snapshot(uuid) to authenticated;
