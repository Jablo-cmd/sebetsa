-- Sebetsa Domain 14 (part 1) — Operations Command Centre + operational
-- alert engine.
--
-- get_command_centre_snapshot() follows get_operational_metrics()'s own
-- established, deliberate design exactly: SECURITY INVOKER, no explicit
-- role check of its own, every figure a live aggregate over tables whose
-- RLS already governs who sees what. That is what makes "don't show the
-- same dashboard to everybody" (this domain's own §20) fall out for free —
-- a site_manager calling this function only ever sees the sites/alerts
-- their own RLS already scopes them to; nothing new is reimplemented here.

create type public.alert_severity as enum ('info', 'warning', 'critical');
create type public.alert_status as enum ('open', 'acknowledged', 'resolved');
create type public.operational_alert_type as enum (
  'site_understaffed', 'employee_absent', 'employee_late', 'patrol_missed',
  'checkpoint_missed', 'qualification_expired', 'contract_sla_breach',
  'incident_overdue', 'critical_task_overdue', 'excessive_overtime',
  'emergency_active'
);

-- ---------------------------------------------------------------------------
-- 14.3 Operational alerts.

create table public.operational_alerts (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  alert_type        public.operational_alert_type not null,
  severity          public.alert_severity not null,
  site_id           uuid references public.sites (id) on delete cascade,
  employee_id       uuid references public.employees (id) on delete cascade,
  contract_id       uuid references public.contracts (id) on delete cascade,
  message           text not null check (char_length(message) > 0),
  status            public.alert_status not null default 'open',
  acknowledged_by   uuid references public.profiles (id) on delete set null,
  acknowledged_at   timestamptz,
  resolved_by       uuid references public.profiles (id) on delete set null,
  resolved_at       timestamptz,
  resolution_notes  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.operational_alerts is
  'System-raised operational alerts. Lifecycle: open -> acknowledged -> resolved, with controlled reopening (resolved -> open) via reopen_operational_alert(). Alerts are raised only by the deterministic sweep functions below or trigger_emergency() — never a direct client INSERT.';

create index operational_alerts_tenant_status_idx on public.operational_alerts (tenant_id, status);
create index operational_alerts_site_id_idx on public.operational_alerts (site_id) where site_id is not null;
create index operational_alerts_employee_id_idx on public.operational_alerts (employee_id) where employee_id is not null;
create index operational_alerts_created_at_idx on public.operational_alerts (created_at);
-- Prevents the sweep functions from raising a second open alert for the
-- same subject + type while one is already unresolved (idempotency).
create unique index operational_alerts_open_dedup_idx on public.operational_alerts (tenant_id, alert_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'), coalesce(employee_id, '00000000-0000-0000-0000-000000000000'), coalesce(contract_id, '00000000-0000-0000-0000-000000000000'))
  where status <> 'resolved';

create trigger operational_alerts_set_updated_at
  before update on public.operational_alerts
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_operational_alert_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.employee_id is not null and not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger operational_alerts_validate_tenant_refs
  before insert or update on public.operational_alerts
  for each row
  execute function public.validate_operational_alert_tenant_refs();

alter table public.operational_alerts enable row level security;
alter table public.operational_alerts force row level security;

create policy operational_alerts_select on public.operational_alerts for select to authenticated
  using (public.can_manage_operations(tenant_id));

-- No direct client write policy — raise_*_alerts() sweep functions and
-- acknowledge/resolve/reopen RPCs only.

create or replace function public.acknowledge_operational_alert(p_alert_id uuid)
returns public.operational_alerts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alert public.operational_alerts;
  v_result public.operational_alerts;
begin
  select * into v_alert from public.operational_alerts where id = p_alert_id for update;
  if not found then
    raise exception 'not_found: no operational alert %', p_alert_id;
  end if;
  if not public.can_manage_operations(v_alert.tenant_id) then
    raise exception 'insufficient_privilege: cannot acknowledge alerts for this tenant';
  end if;
  -- The safety-critical case (an emergency-active alert about the caller's
  -- own triggered emergency) needs the same independent-oversight guard
  -- acknowledge_emergency() itself now has — closing the bypass of calling
  -- this table-level RPC directly instead of the emergency-specific one.
  if v_alert.alert_type = 'emergency_active' and v_alert.employee_id is not null
     and exists (select 1 from public.employees where id = v_alert.employee_id and profile_id = auth.uid())
     and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot acknowledge an emergency alert about your own emergency — independent response oversight is required';
  end if;
  if v_alert.status <> 'open' then
    raise exception 'invalid_transition: only an open alert can be acknowledged (current status: %)', v_alert.status;
  end if;

  update public.operational_alerts set status = 'acknowledged', acknowledged_by = auth.uid(), acknowledged_at = now()
    where id = p_alert_id returning * into v_result;

  perform public.write_audit_log(v_alert.tenant_id, auth.uid(), 'operational_alert_acknowledged', 'operational_alerts', p_alert_id, jsonb_build_object('status', 'open'), jsonb_build_object('status', 'acknowledged'));
  return v_result;
end;
$$;

revoke execute on function public.acknowledge_operational_alert(uuid) from public, anon;
grant execute on function public.acknowledge_operational_alert(uuid) to authenticated;

create or replace function public.resolve_operational_alert(p_alert_id uuid, p_resolution_notes text default null)
returns public.operational_alerts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alert public.operational_alerts;
  v_result public.operational_alerts;
begin
  select * into v_alert from public.operational_alerts where id = p_alert_id for update;
  if not found then
    raise exception 'not_found: no operational alert %', p_alert_id;
  end if;
  if not public.can_manage_operations(v_alert.tenant_id) then
    raise exception 'insufficient_privilege: cannot resolve alerts for this tenant';
  end if;
  if v_alert.alert_type = 'emergency_active' and v_alert.employee_id is not null
     and exists (select 1 from public.employees where id = v_alert.employee_id and profile_id = auth.uid())
     and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot resolve an emergency alert about your own emergency — independent response oversight is required';
  end if;
  if v_alert.status = 'resolved' then
    raise exception 'invalid_transition: alert is already resolved';
  end if;

  update public.operational_alerts set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_notes = p_resolution_notes
    where id = p_alert_id returning * into v_result;

  perform public.write_audit_log(v_alert.tenant_id, auth.uid(), 'operational_alert_resolved', 'operational_alerts', p_alert_id, jsonb_build_object('status', v_alert.status), jsonb_build_object('status', 'resolved', 'resolution_notes', p_resolution_notes));
  return v_result;
end;
$$;

revoke execute on function public.resolve_operational_alert(uuid, text) from public, anon;
grant execute on function public.resolve_operational_alert(uuid, text) to authenticated;

create or replace function public.reopen_operational_alert(p_alert_id uuid, p_reason text)
returns public.operational_alerts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alert public.operational_alerts;
  v_result public.operational_alerts;
begin
  select * into v_alert from public.operational_alerts where id = p_alert_id for update;
  if not found then
    raise exception 'not_found: no operational alert %', p_alert_id;
  end if;
  if not public.can_manage_operations(v_alert.tenant_id) then
    raise exception 'insufficient_privilege: cannot reopen alerts for this tenant';
  end if;
  if v_alert.status <> 'resolved' then
    raise exception 'invalid_transition: only a resolved alert can be reopened (current status: %)', v_alert.status;
  end if;

  update public.operational_alerts set status = 'open', resolution_notes = coalesce(v_alert.resolution_notes, '') || format(' [reopened: %s]', p_reason)
    where id = p_alert_id returning * into v_result;

  perform public.write_audit_log(v_alert.tenant_id, auth.uid(), 'operational_alert_reopened', 'operational_alerts', p_alert_id, jsonb_build_object('status', 'resolved'), jsonb_build_object('status', 'open', 'reason', p_reason));
  return v_result;
end;
$$;

revoke execute on function public.reopen_operational_alert(uuid, text) from public, anon;
grant execute on function public.reopen_operational_alert(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Deterministic alert-raising sweeps. Same posture as sync_all_expired_*
-- (20260919090700): tenant-batch, service-role/cron-only, idempotent via
-- operational_alerts_open_dedup_idx (an ON CONFLICT DO NOTHING against an
-- already-open alert for the same subject, not a duplicate).

create or replace function public.raise_understaffed_site_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    select ssr.tenant_id, ssr.site_id, s.name as site_name,
           sum(ssr.required_count) as required, count(distinct sa.employee_id) as assigned
    from public.site_staffing_requirements ssr
    join public.sites s on s.id = ssr.site_id and s.status = 'active'
    left join public.site_assignments sa on sa.site_id = ssr.site_id and (sa.end_date is null or sa.end_date >= current_date)
    group by ssr.tenant_id, ssr.site_id, s.name
    having count(distinct sa.employee_id) < sum(ssr.required_count)
  loop
    insert into public.operational_alerts (tenant_id, alert_type, severity, site_id, message)
    values (
      v_row.tenant_id, 'site_understaffed',
      case when v_row.assigned = 0 then 'critical' else 'warning' end::public.alert_severity,
      v_row.site_id,
      format('%s is understaffed: %s assigned vs %s required', v_row.site_name, v_row.assigned, v_row.required)
    )
    on conflict (tenant_id, alert_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'), coalesce(employee_id, '00000000-0000-0000-0000-000000000000'), coalesce(contract_id, '00000000-0000-0000-0000-000000000000')) where status <> 'resolved'
    do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.raise_understaffed_site_alerts() from public, anon, authenticated;

create or replace function public.raise_missed_patrol_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    select r.tenant_id, r.site_id, r.id as patrol_run_id, s.name as site_name
    from public.patrol_runs r
    join public.patrol_routes pr on pr.id = r.patrol_route_id
    join public.sites s on s.id = r.site_id
    where r.status = 'in_progress'
      and r.started_at < now() - make_interval(mins => pr.allowed_start_window_minutes + coalesce(pr.expected_duration_minutes, 60))
  loop
    insert into public.operational_alerts (tenant_id, alert_type, severity, site_id, message)
    values (v_row.tenant_id, 'patrol_missed', 'warning', v_row.site_id, format('A patrol at %s has exceeded its expected window and was not completed', v_row.site_name))
    on conflict (tenant_id, alert_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'), coalesce(employee_id, '00000000-0000-0000-0000-000000000000'), coalesce(contract_id, '00000000-0000-0000-0000-000000000000')) where status <> 'resolved'
    do nothing;
    update public.patrol_runs set status = 'abandoned' where id = v_row.patrol_run_id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.raise_missed_patrol_alerts() from public, anon, authenticated;

create or replace function public.raise_contract_sla_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    select sd.tenant_id, sd.contract_id, c.contract_number, sd.name as sla_name
    from public.sla_definitions sd
    join public.contracts c on c.id = sd.contract_id
    join lateral (
      select target_met from public.sla_measurements m where m.sla_definition_id = sd.id order by m.period_end desc limit 1
    ) latest on true
    where sd.is_active and not latest.target_met
  loop
    insert into public.operational_alerts (tenant_id, alert_type, severity, contract_id, message)
    values (v_row.tenant_id, 'contract_sla_breach', 'critical', v_row.contract_id, format('Contract %s is breaching its "%s" SLA target', v_row.contract_number, v_row.sla_name))
    on conflict (tenant_id, alert_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'), coalesce(employee_id, '00000000-0000-0000-0000-000000000000'), coalesce(contract_id, '00000000-0000-0000-0000-000000000000')) where status <> 'resolved'
    do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.raise_contract_sla_alerts() from public, anon, authenticated;

create or replace function public.raise_overdue_incident_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    select tenant_id, id as incident_id, reference_number
    from public.incidents
    where status not in ('closed') and occurred_at < now() - interval '48 hours'
  loop
    insert into public.operational_alerts (tenant_id, alert_type, severity, message)
    values (v_row.tenant_id, 'incident_overdue', 'warning', format('Incident %s has been open for over 48 hours', v_row.reference_number))
    on conflict (tenant_id, alert_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'), coalesce(employee_id, '00000000-0000-0000-0000-000000000000'), coalesce(contract_id, '00000000-0000-0000-0000-000000000000')) where status <> 'resolved'
    do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.raise_overdue_incident_alerts() from public, anon, authenticated;

-- Runs every raise_*_alerts() sweep in one call — the unit that pg_cron (or
-- a manual "refresh alerts" action) invokes. Same pg_cron-availability
-- guard pattern as 20260919090700_p1_expiry_sweep_scheduling.sql.
create or replace function public.run_operational_alert_sweeps()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.raise_understaffed_site_alerts();
  perform public.raise_missed_patrol_alerts();
  perform public.raise_contract_sla_alerts();
  perform public.raise_overdue_incident_alerts();
end;
$$;

revoke execute on function public.run_operational_alert_sweeps() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('sebetsa-operational-alert-sweep', '*/15 * * * *', $sql$select public.run_operational_alert_sweeps();$sql$);
  else
    raise notice 'pg_cron extension not available in this environment — operational_alerts sweep function created, but not scheduled. Enable pg_cron under Database > Extensions on the hosted Supabase project and re-run this migration''s DO block (or manually call select cron.schedule(...) with the command shown above).';
  end if;
end $$;

-- get_command_centre_snapshot() is defined in the next migration
-- (20260921090300_emergency_response.sql), after emergency_events/
-- emergency_responses exist — it aggregates across both alerts and
-- emergencies, so it belongs after both are real tables.
