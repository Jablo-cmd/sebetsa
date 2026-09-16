-- Sebetsa Domain 13 (part 2) — Guard tours / checkpoints.
--
-- A real patrol system, not a task checklist with a different label: a
-- checkpoint has a physical identity (QR/NFC code) a device scans, a patrol
-- route defines an expected sequence and timing, and a patrol run is the
-- append-only record of what a specific employee actually scanned, when,
-- in what order, with server-computed risk flags for the anti-abuse
-- patterns named in the brief. No component of this trusts a client-
-- supplied "I visited checkpoint X" without validating it against the
-- route it belongs to, the employee's own site assignment, and the run's
-- own scan history.

create type public.checkpoint_scan_type as enum ('qr', 'nfc');
create type public.patrol_run_status as enum ('in_progress', 'completed', 'incomplete', 'abandoned');
create type public.checkpoint_scan_result as enum (
  'valid', 'wrong_sequence', 'duplicate', 'out_of_window', 'invalid_checkpoint', 'not_assigned'
);

-- ---------------------------------------------------------------------------
-- 13B.1 Checkpoints. `scan_type` is qr|nfc today; nothing about this shape
-- (a stable per-site `code` a device reads) prevents a future
-- 'ble_beacon' value being added to the enum later without a redesign.

create table public.checkpoints (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  site_id     uuid not null references public.sites (id) on delete cascade,
  code        text not null check (char_length(code) > 0),
  name        text not null check (char_length(name) > 0),
  latitude    numeric(9, 6),
  longitude   numeric(9, 6),
  scan_type   public.checkpoint_scan_type not null default 'qr',
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (site_id, code)
);

create index checkpoints_tenant_id_idx on public.checkpoints (tenant_id);
create index checkpoints_site_id_idx on public.checkpoints (site_id);

create trigger checkpoints_set_updated_at
  before update on public.checkpoints
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_checkpoint_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger checkpoints_validate_tenant_refs
  before insert or update on public.checkpoints
  for each row
  execute function public.validate_checkpoint_tenant_refs();

alter table public.checkpoints enable row level security;
alter table public.checkpoints force row level security;

create policy checkpoints_select on public.checkpoints for select to authenticated
  using (public.can_manage_operations(tenant_id));

create policy checkpoints_write on public.checkpoints for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

-- ---------------------------------------------------------------------------
-- 13B.2 Patrol routes + their ordered checkpoint sequence.

create table public.patrol_routes (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.organizations (id) on delete cascade,
  site_id                   uuid not null references public.sites (id) on delete cascade,
  name                      text not null check (char_length(name) > 0),
  expected_duration_minutes integer check (expected_duration_minutes is null or expected_duration_minutes > 0),
  allowed_start_window_minutes integer not null default 60 check (allowed_start_window_minutes > 0),
  completion_threshold_pct  integer not null default 100 check (completion_threshold_pct between 1 and 100),
  active                    boolean not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index patrol_routes_tenant_id_idx on public.patrol_routes (tenant_id);
create index patrol_routes_site_id_idx on public.patrol_routes (site_id);

create trigger patrol_routes_set_updated_at
  before update on public.patrol_routes
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_patrol_route_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger patrol_routes_validate_tenant_refs
  before insert or update on public.patrol_routes
  for each row
  execute function public.validate_patrol_route_tenant_refs();

alter table public.patrol_routes enable row level security;
alter table public.patrol_routes force row level security;

create policy patrol_routes_select on public.patrol_routes for select to authenticated
  using (public.can_manage_operations(tenant_id));

create policy patrol_routes_write on public.patrol_routes for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create table public.patrol_route_checkpoints (
  id                    uuid primary key default gen_random_uuid(),
  patrol_route_id       uuid not null references public.patrol_routes (id) on delete cascade,
  checkpoint_id         uuid not null references public.checkpoints (id) on delete cascade,
  sequence_number       integer not null check (sequence_number > 0),
  tolerance_window_minutes integer not null default 15 check (tolerance_window_minutes > 0),
  unique (patrol_route_id, sequence_number),
  unique (patrol_route_id, checkpoint_id)
);

create index patrol_route_checkpoints_route_idx on public.patrol_route_checkpoints (patrol_route_id, sequence_number);

-- A route's checkpoint must belong to the same site as the route itself —
-- not merely the same tenant. Structural, not just tenant, integrity.
create or replace function public.validate_patrol_route_checkpoint_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_route_site uuid;
  v_checkpoint_site uuid;
begin
  select site_id into v_route_site from public.patrol_routes where id = new.patrol_route_id;
  select site_id into v_checkpoint_site from public.checkpoints where id = new.checkpoint_id;
  if v_route_site is null or v_checkpoint_site is null or v_route_site <> v_checkpoint_site then
    raise exception 'invalid_reference: checkpoint % does not belong to the same site as route %', new.checkpoint_id, new.patrol_route_id;
  end if;
  return new;
end;
$$;

create trigger patrol_route_checkpoints_validate_refs
  before insert or update on public.patrol_route_checkpoints
  for each row
  execute function public.validate_patrol_route_checkpoint_refs();

alter table public.patrol_route_checkpoints enable row level security;
alter table public.patrol_route_checkpoints force row level security;

create policy patrol_route_checkpoints_select on public.patrol_route_checkpoints for select to authenticated
  using (exists (select 1 from public.patrol_routes r where r.id = patrol_route_checkpoints.patrol_route_id and public.can_manage_operations(r.tenant_id)));

create policy patrol_route_checkpoints_write on public.patrol_route_checkpoints for all to authenticated
  using (exists (select 1 from public.patrol_routes r where r.id = patrol_route_checkpoints.patrol_route_id and public.can_manage_operations(r.tenant_id)))
  with check (exists (select 1 from public.patrol_routes r where r.id = patrol_route_checkpoints.patrol_route_id and public.can_manage_operations(r.tenant_id)));

-- ---------------------------------------------------------------------------
-- 13B.3/13B.4 Patrol execution — append-only scan log, mutable run summary.

create table public.patrol_runs (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.organizations (id) on delete cascade,
  patrol_route_id           uuid not null references public.patrol_routes (id) on delete cascade,
  site_id                   uuid not null references public.sites (id) on delete cascade,
  employee_id               uuid not null references public.employees (id) on delete cascade,
  status                    public.patrol_run_status not null default 'in_progress',
  started_at                timestamptz not null default now(),
  completed_at              timestamptz,
  expected_checkpoint_count integer not null,
  scanned_checkpoint_count  integer not null default 0,
  created_at                timestamptz not null default now()
);

create index patrol_runs_tenant_id_idx on public.patrol_runs (tenant_id);
create index patrol_runs_employee_id_idx on public.patrol_runs (employee_id, started_at);
create index patrol_runs_site_id_idx on public.patrol_runs (site_id, started_at);
create index patrol_runs_open_idx on public.patrol_runs (employee_id) where status = 'in_progress';

create or replace function public.validate_patrol_run_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.patrol_routes where id = new.patrol_route_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: patrol route % does not belong to tenant %', new.patrol_route_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger patrol_runs_validate_tenant_refs
  before insert on public.patrol_runs
  for each row
  execute function public.validate_patrol_run_tenant_refs();

alter table public.patrol_runs enable row level security;
alter table public.patrol_runs force row level security;

create policy patrol_runs_select on public.patrol_runs for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = patrol_runs.employee_id and e.profile_id = auth.uid())
  );

-- No direct client write policy — start_patrol()/complete_patrol() RPCs only.

create table public.patrol_checkpoint_scans (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  patrol_run_id       uuid not null references public.patrol_runs (id) on delete cascade,
  checkpoint_id       uuid references public.checkpoints (id) on delete cascade,
  scanned_code        text,
  employee_id         uuid not null references public.employees (id) on delete cascade,
  sequence_number     integer not null,
  scanned_at          timestamptz not null default now(),
  scan_method         public.checkpoint_scan_type not null,
  latitude             numeric(9, 6),
  longitude            numeric(9, 6),
  verification_result public.checkpoint_scan_result not null,
  risk_flags          jsonb not null default '[]'::jsonb
);

comment on table public.patrol_checkpoint_scans is
  'Append-only — no UPDATE/DELETE policy for authenticated. Every scan attempt is recorded, valid or not (a wrong_sequence/duplicate/out_of_window scan is still evidence of what happened, never discarded). checkpoint_id is nullable: a scan of a code that matches no real checkpoint at this site (verification_result=invalid_checkpoint) has no checkpoint entity to reference, but scanned_code preserves what was actually scanned as evidence.';

create index patrol_checkpoint_scans_run_idx on public.patrol_checkpoint_scans (patrol_run_id, scanned_at);
create index patrol_checkpoint_scans_tenant_id_idx on public.patrol_checkpoint_scans (tenant_id);

create or replace function public.validate_patrol_checkpoint_scan_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.patrol_runs where id = new.patrol_run_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: patrol run % does not belong to tenant %', new.patrol_run_id, new.tenant_id;
  end if;
  if new.checkpoint_id is not null and not exists (select 1 from public.checkpoints where id = new.checkpoint_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: checkpoint % does not belong to tenant %', new.checkpoint_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger patrol_checkpoint_scans_validate_tenant_refs
  before insert on public.patrol_checkpoint_scans
  for each row
  execute function public.validate_patrol_checkpoint_scan_tenant_refs();

alter table public.patrol_checkpoint_scans enable row level security;
alter table public.patrol_checkpoint_scans force row level security;

create policy patrol_checkpoint_scans_select on public.patrol_checkpoint_scans for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = patrol_checkpoint_scans.employee_id and e.profile_id = auth.uid())
  );

-- No direct client write policy — scan_checkpoint() RPC only.

-- ---------------------------------------------------------------------------
-- 13B.3 Patrol execution RPCs.

create or replace function public.start_patrol(p_patrol_route_id uuid)
returns public.patrol_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_route public.patrol_routes;
  v_expected_count integer;
  v_result public.patrol_runs;
begin
  select id into v_employee_id from public.employees where profile_id = auth.uid();
  if not found then
    raise exception 'not_found: no employee record linked to your account';
  end if;

  if not public.employee_can_self_serve(v_employee_id) then
    raise exception 'inactive_employee: this employee is terminated or suspended and cannot start a patrol';
  end if;

  select * into v_route from public.patrol_routes where id = p_patrol_route_id for update;
  if not found then
    raise exception 'not_found: no patrol route %', p_patrol_route_id;
  end if;
  if not v_route.active then
    raise exception 'invalid_request: this patrol route is not active';
  end if;

  if not exists (
    select 1 from public.site_assignments
    where employee_id = v_employee_id and site_id = v_route.site_id
      and (end_date is null or end_date >= current_date)
  ) then
    raise exception 'not_assigned: you are not currently assigned to this route''s site';
  end if;

  if exists (select 1 from public.patrol_runs where employee_id = v_employee_id and status = 'in_progress') then
    raise exception 'already_in_progress: you already have a patrol in progress';
  end if;

  select count(*) into v_expected_count from public.patrol_route_checkpoints where patrol_route_id = p_patrol_route_id;
  if v_expected_count = 0 then
    raise exception 'invalid_request: this patrol route has no checkpoints configured';
  end if;

  insert into public.patrol_runs (tenant_id, patrol_route_id, site_id, employee_id, expected_checkpoint_count)
  values (v_route.tenant_id, p_patrol_route_id, v_route.site_id, v_employee_id, v_expected_count)
  returning * into v_result;

  perform public.write_audit_log(v_route.tenant_id, auth.uid(), 'patrol_started', 'patrol_runs', v_result.id, null, jsonb_build_object('patrol_route_id', p_patrol_route_id));

  return v_result;
end;
$$;

revoke execute on function public.start_patrol(uuid) from public, anon;
grant execute on function public.start_patrol(uuid) to authenticated;

-- scan_checkpoint(): every anti-abuse check named in the brief is
-- evaluated and the *result* is always recorded — a bad scan doesn't error
-- out silently, it becomes evidence with a risk flag, which is the right
-- posture for something a real guard's flaky phone will trigger constantly
-- through no fault of their own (duplicate scan from a network retry,
-- being slightly out of the tolerance window because of a slow lift).
-- Genuine authorization failures (not this employee's run, checkpoint from
-- a different tenant) still hard-fail.
create or replace function public.scan_checkpoint(
  p_patrol_run_id uuid,
  p_checkpoint_code text,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_scan_method public.checkpoint_scan_type default 'qr'
)
returns table (scan public.patrol_checkpoint_scans, run public.patrol_runs)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_run public.patrol_runs;
  v_checkpoint public.checkpoints;
  v_route_checkpoint public.patrol_route_checkpoints;
  v_expected_sequence integer;
  v_last_scan_at timestamptz;
  v_result public.checkpoint_scan_result;
  v_risk_flags jsonb := '[]'::jsonb;
  v_scan public.patrol_checkpoint_scans;
begin
  select id into v_employee_id from public.employees where profile_id = auth.uid();
  if not found then
    raise exception 'not_found: no employee record linked to your account';
  end if;

  select * into v_run from public.patrol_runs where id = p_patrol_run_id for update;
  if not found then
    raise exception 'not_found: no patrol run %', p_patrol_run_id;
  end if;
  if v_run.employee_id <> v_employee_id then
    raise exception 'insufficient_privilege: this is not your patrol run';
  end if;
  if v_run.status <> 'in_progress' then
    raise exception 'invalid_request: this patrol run is no longer in progress (status: %)', v_run.status;
  end if;

  select c.* into v_checkpoint from public.checkpoints c where c.site_id = v_run.site_id and c.code = p_checkpoint_code and c.active;
  if not found then
    v_result := 'invalid_checkpoint';
  else
    select prc.* into v_route_checkpoint from public.patrol_route_checkpoints prc
      where prc.patrol_route_id = v_run.patrol_route_id and prc.checkpoint_id = v_checkpoint.id;
    if not found then
      v_result := 'invalid_checkpoint';
    elsif exists (select 1 from public.patrol_checkpoint_scans where patrol_run_id = p_patrol_run_id and checkpoint_id = v_checkpoint.id and verification_result = 'valid') then
      v_result := 'duplicate';
    else
      -- Only *valid* prior scans count toward "what checkpoint comes
      -- next" / "when did the guard last actually reach a checkpoint" —
      -- a rejected attempt (wrong_sequence/out_of_window/duplicate/
      -- invalid_checkpoint) still gets recorded as evidence below, but
      -- must not itself corrupt the sequence/timing baseline for every
      -- scan that follows it.
      select coalesce(max(sequence_number), 0) + 1 into v_expected_sequence from public.patrol_checkpoint_scans where patrol_run_id = p_patrol_run_id and verification_result = 'valid';

      select max(scanned_at) into v_last_scan_at from public.patrol_checkpoint_scans where patrol_run_id = p_patrol_run_id and verification_result = 'valid';

      if v_route_checkpoint.sequence_number <> v_expected_sequence then
        v_result := 'wrong_sequence';
        v_risk_flags := v_risk_flags || jsonb_build_object('expected_sequence', v_expected_sequence, 'scanned_sequence', v_route_checkpoint.sequence_number);
      elsif extract(epoch from (now() - coalesce(v_last_scan_at, v_run.started_at))) / 60.0 > v_route_checkpoint.tolerance_window_minutes then
        v_result := 'out_of_window';
        v_risk_flags := v_risk_flags || jsonb_build_object('minutes_since_previous', round(extract(epoch from (now() - coalesce(v_last_scan_at, v_run.started_at))) / 60.0), 'tolerance_window_minutes', v_route_checkpoint.tolerance_window_minutes);
      -- Impossible-travel-time guard: two checkpoints scanned less than 10
      -- seconds apart is not a real walked patrol — flagged, not silently
      -- accepted, without claiming to detect every form of spoofing.
      elsif v_last_scan_at is not null and extract(epoch from (now() - v_last_scan_at)) < 10 then
        v_result := 'valid';
        v_risk_flags := v_risk_flags || jsonb_build_object('warning', 'implausibly_fast_travel_from_previous_checkpoint', 'seconds_since_previous', round(extract(epoch from (now() - v_last_scan_at))));
      else
        v_result := 'valid';
      end if;
    end if;
  end if;

  insert into public.patrol_checkpoint_scans (
    tenant_id, patrol_run_id, checkpoint_id, scanned_code, employee_id, sequence_number, scan_method, latitude, longitude, verification_result, risk_flags
  ) values (
    v_run.tenant_id, p_patrol_run_id, coalesce(v_checkpoint.id, (select id from public.checkpoints where site_id = v_run.site_id and code = p_checkpoint_code limit 1)),
    p_checkpoint_code, v_employee_id, coalesce(v_route_checkpoint.sequence_number, 0), p_scan_method, p_latitude, p_longitude, v_result, v_risk_flags
  ) returning * into v_scan;

  if v_result = 'valid' then
    update public.patrol_runs set scanned_checkpoint_count = scanned_checkpoint_count + 1 where id = p_patrol_run_id returning * into v_run;
  end if;

  return query select v_scan, v_run;
end;
$$;

revoke execute on function public.scan_checkpoint(uuid, text, numeric, numeric, public.checkpoint_scan_type) from public, anon;
grant execute on function public.scan_checkpoint(uuid, text, numeric, numeric, public.checkpoint_scan_type) to authenticated;

create or replace function public.complete_patrol(p_patrol_run_id uuid)
returns public.patrol_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_run public.patrol_runs;
  v_pct numeric;
  v_route public.patrol_routes;
  v_result public.patrol_runs;
begin
  select id into v_employee_id from public.employees where profile_id = auth.uid();
  select * into v_run from public.patrol_runs where id = p_patrol_run_id for update;
  if not found then
    raise exception 'not_found: no patrol run %', p_patrol_run_id;
  end if;
  if v_run.employee_id <> v_employee_id and not public.can_manage_operations(v_run.tenant_id) then
    raise exception 'insufficient_privilege: this is not your patrol run';
  end if;
  if v_run.status <> 'in_progress' then
    raise exception 'invalid_request: this patrol run is not in progress (status: %)', v_run.status;
  end if;

  select * into v_route from public.patrol_routes where id = v_run.patrol_route_id;
  v_pct := (v_run.scanned_checkpoint_count::numeric / greatest(v_run.expected_checkpoint_count, 1)) * 100;

  update public.patrol_runs
    set status = case when v_pct >= v_route.completion_threshold_pct then 'completed' else 'incomplete' end::public.patrol_run_status,
        completed_at = now()
    where id = p_patrol_run_id
    returning * into v_result;

  perform public.write_audit_log(v_run.tenant_id, auth.uid(), 'patrol_completed', 'patrol_runs', p_patrol_run_id, null,
    jsonb_build_object('status', v_result.status, 'scanned', v_run.scanned_checkpoint_count, 'expected', v_run.expected_checkpoint_count));

  return v_result;
end;
$$;

revoke execute on function public.complete_patrol(uuid) from public, anon;
grant execute on function public.complete_patrol(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 13B.5 Patrol dashboard aggregation — SECURITY INVOKER, RLS-riding, same
-- design as get_operational_metrics(): every figure is scoped by the
-- caller's own existing RLS on patrol_runs/patrol_checkpoint_scans, so no
-- separate role-filtering logic is duplicated here.

create or replace function public.get_patrol_summary(p_tenant_id uuid, p_since timestamptz default (now() - interval '7 days'))
returns table (
  active_patrols bigint,
  completed_patrols bigint,
  incomplete_patrols bigint,
  missed_checkpoints bigint,
  late_checkpoints bigint,
  exception_rate numeric
)
language sql
stable
as $$
  select
    count(*) filter (where status = 'in_progress'),
    count(*) filter (where status = 'completed'),
    count(*) filter (where status = 'incomplete'),
    coalesce((select count(*) from public.patrol_checkpoint_scans s join public.patrol_runs r on r.id = s.patrol_run_id where r.tenant_id = p_tenant_id and r.started_at >= p_since and s.verification_result = 'invalid_checkpoint'), 0),
    coalesce((select count(*) from public.patrol_checkpoint_scans s join public.patrol_runs r on r.id = s.patrol_run_id where r.tenant_id = p_tenant_id and r.started_at >= p_since and s.verification_result = 'out_of_window'), 0),
    coalesce((select round(100.0 * count(*) filter (where s.verification_result <> 'valid') / greatest(count(*), 1), 1)
              from public.patrol_checkpoint_scans s join public.patrol_runs r on r.id = s.patrol_run_id where r.tenant_id = p_tenant_id and r.started_at >= p_since), 0)
  from public.patrol_runs
  where tenant_id = p_tenant_id and started_at >= p_since
$$;

revoke execute on function public.get_patrol_summary(uuid, timestamptz) from public, anon;
grant execute on function public.get_patrol_summary(uuid, timestamptz) to authenticated;
