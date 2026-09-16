-- Sebetsa Domain 13 (part 1) — GPS-verified field presence.
--
-- Not "add lat/lng to attendance": a proper evidence model. The immutable
-- fact ("what did the device report, and what did the server decide") is
-- attendance_location_events, append-only, never updated. attendance_records
-- keeps only a denormalized summary status for fast dashboard filtering —
-- the same pattern leave_balances (snapshot) vs leave_balance_transactions
-- (ledger) already established in this codebase.
--
-- The server is authoritative: the frontend reports raw coordinates and
-- accuracy; every distance calculation and verification decision happens
-- here, in SQL, inside the same SECURITY DEFINER transaction as the
-- clock_in/clock_out write. A client claiming "is_within_geofence: true" is
-- never trusted — that field does not exist as a client input anywhere in
-- this migration.

create type public.gps_verification_status as enum (
  'verified',            -- inside the configured geofence, within accuracy threshold
  'outside_geofence',    -- valid location, but outside the site's radius
  'low_accuracy',        -- a location was reported but accuracy exceeds the site's threshold
  'location_unavailable',-- device could not produce a location at all
  'pending_verification',-- no geofence configured for this site yet (nothing to check against)
  'offline_pending',     -- the event was captured offline and is awaiting sync (client-set, see 13.13 below)
  'manual_review',       -- flagged for supervisor attention (used by attendance_location_exceptions)
  'not_applicable'       -- clock-in was performed by a manager on the employee's behalf, not a device GPS read
);

-- ---------------------------------------------------------------------------
-- 13.1 Site geofencing. One active geofence per site for this first
-- production implementation (radius-based) — the table shape (a plain row
-- per site, not columns bolted onto `sites`) means a future polygon/shape
-- model can be added as new columns or a sibling table without touching
-- this one's meaning, and the config-audit fields make "who changed this
-- and when" a first-class fact rather than something inferred from
-- audit_log alone.

create table public.site_geofences (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.organizations (id) on delete cascade,
  site_id                 uuid not null references public.sites (id) on delete cascade,
  latitude                numeric(9, 6) not null check (latitude between -90 and 90),
  longitude               numeric(9, 6) not null check (longitude between -180 and 180),
  radius_meters           integer not null check (radius_meters > 0 and radius_meters <= 5000),
  accuracy_threshold_meters integer not null default 100 check (accuracy_threshold_meters > 0),
  enabled                 boolean not null default true,
  configured_by           uuid references public.profiles (id) on delete set null,
  configured_at           timestamptz not null default now(),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (site_id)
);

comment on table public.site_geofences is
  'One row per site. Radius-based for this release; latitude/longitude/radius_meters is the v1 shape. A future polygon geofence would add its own columns (e.g. boundary geography) rather than repurpose these, so v1 rows stay meaningful unmigrated.';

create index site_geofences_tenant_id_idx on public.site_geofences (tenant_id);

create trigger site_geofences_set_updated_at
  before update on public.site_geofences
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_site_geofence_tenant_refs()
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

create trigger site_geofences_validate_tenant_refs
  before insert or update on public.site_geofences
  for each row
  execute function public.validate_site_geofence_tenant_refs();

alter table public.site_geofences enable row level security;
alter table public.site_geofences force row level security;

-- Same visibility as the site itself (org_structure.view tier) — a
-- geofence is site configuration, not a separate access domain.
create policy site_geofences_select on public.site_geofences for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

create policy site_geofences_write on public.site_geofences for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger site_geofences_audit_log
  after insert or update on public.site_geofences
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Haversine great-circle distance in meters. Immutable/stable pure math —
-- no table access — so it is safe to call from both SECURITY DEFINER RPCs
-- and, later, a read-only dashboard query.
create or replace function public.gps_distance_meters(
  p_lat1 numeric, p_lon1 numeric, p_lat2 numeric, p_lon2 numeric
) returns numeric
language sql
immutable
as $$
  select 6371000 * 2 * asin(
    sqrt(
      power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
      cos(radians(p_lat1)) * cos(radians(p_lat2)) *
      power(sin(radians(p_lon2 - p_lon1) / 2), 2)
    )
  )
$$;

comment on function public.gps_distance_meters(numeric, numeric, numeric, numeric) is
  'Haversine great-circle distance in meters between two lat/lon points. Pure math, no PII, safe to expose broadly.';

-- ---------------------------------------------------------------------------
-- 13.3 Location evidence — append-only. One row per clock-in/clock-out GPS
-- capture attempt, whether it succeeded or not; a failed/denied/low-accuracy
-- attempt is still evidence and is still recorded, never silently dropped.

create table public.attendance_location_events (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  attendance_record_id  uuid not null references public.attendance_records (id) on delete cascade,
  employee_id           uuid not null references public.employees (id) on delete cascade,
  site_id               uuid not null references public.sites (id) on delete cascade,
  event_type            text not null check (event_type in ('clock_in', 'clock_out')),
  latitude              numeric(9, 6) check (latitude is null or latitude between -90 and 90),
  longitude             numeric(9, 6) check (longitude is null or longitude between -180 and 180),
  accuracy_meters       numeric(8, 2) check (accuracy_meters is null or accuracy_meters >= 0),
  client_captured_at    timestamptz,
  distance_meters       numeric(10, 2),
  geofence_radius_meters integer,
  verification_status   public.gps_verification_status not null,
  verification_reason   text not null,
  device_context        jsonb not null default '{}'::jsonb,
  recorded_at           timestamptz not null default now()
);

comment on table public.attendance_location_events is
  'Append-only evidence log — no UPDATE/DELETE policy for authenticated. One row per GPS capture attempt at clock-in/clock-out, success or failure alike. device_context is deliberately minimal (user agent / platform class only — never IMEI, never precise device identifiers) per privacy-by-design; see docs.';

create index attendance_location_events_attendance_record_idx on public.attendance_location_events (attendance_record_id);
create index attendance_location_events_tenant_id_idx on public.attendance_location_events (tenant_id);
create index attendance_location_events_employee_id_idx on public.attendance_location_events (employee_id, recorded_at);

create or replace function public.validate_attendance_location_event_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.attendance_records where id = new.attendance_record_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: attendance record % does not belong to tenant %', new.attendance_record_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger attendance_location_events_validate_tenant_refs
  before insert on public.attendance_location_events
  for each row
  execute function public.validate_attendance_location_event_tenant_refs();

alter table public.attendance_location_events enable row level security;
alter table public.attendance_location_events force row level security;

-- Location evidence is more sensitive than the attendance record itself —
-- visible only to the operations-management tier and the employee's own
-- events, never a blanket "any tenant member" read (privacy-by-design,
-- ADAPTATION 14 of this domain's brief). No INSERT/UPDATE/DELETE policy for
-- `authenticated` at all — only the clock_in/clock_out SECURITY DEFINER
-- RPCs (running as the function owner) can write here.
create policy attendance_location_events_select on public.attendance_location_events for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = attendance_location_events.employee_id and e.profile_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 13.5 Manual exception workflow. The original GPS evidence
-- (attendance_location_events) is never edited or deleted by this
-- workflow — an exception is a separate decision layered on top.

create table public.attendance_location_exceptions (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  attendance_record_id  uuid not null references public.attendance_records (id) on delete cascade,
  employee_id           uuid not null references public.employees (id) on delete cascade,
  reason                text not null check (char_length(reason) > 0),
  status                text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by           uuid references public.profiles (id) on delete set null,
  reviewed_at           timestamptz,
  review_notes          text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.attendance_location_exceptions is
  'A supervisor-reviewed exception request for a clock-in that failed GPS verification (outside_geofence/location_unavailable/low_accuracy). Approving an exception does not alter or delete the original attendance_location_events row — the evidence stands; this table records the human decision made in light of it.';

create index attendance_location_exceptions_tenant_id_idx on public.attendance_location_exceptions (tenant_id);
create index attendance_location_exceptions_attendance_record_idx on public.attendance_location_exceptions (attendance_record_id);
create index attendance_location_exceptions_status_idx on public.attendance_location_exceptions (status);

create trigger attendance_location_exceptions_set_updated_at
  before update on public.attendance_location_exceptions
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_attendance_location_exception_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.attendance_records where id = new.attendance_record_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: attendance record % does not belong to tenant %', new.attendance_record_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger attendance_location_exceptions_validate_tenant_refs
  before insert or update on public.attendance_location_exceptions
  for each row
  execute function public.validate_attendance_location_exception_tenant_refs();

alter table public.attendance_location_exceptions enable row level security;
alter table public.attendance_location_exceptions force row level security;

create policy attendance_location_exceptions_select on public.attendance_location_exceptions for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = attendance_location_exceptions.employee_id and e.profile_id = auth.uid())
  );

-- No direct client write policy — request_attendance_location_exception()/
-- decide_attendance_location_exception() RPCs only, same "no direct table
-- write" posture as asset_assignments.

-- ---------------------------------------------------------------------------
-- attendance_records gains a denormalized summary column for fast
-- dashboard filtering (e.g. "show me every unconfirmed arrival that failed
-- geofence today") without joining the evidence table on every list query.
-- The detailed evidence always lives in attendance_location_events; this
-- column is a read-optimization, never the source of truth.

alter table public.attendance_records
  add column gps_verification_status public.gps_verification_status not null default 'not_applicable';

create index attendance_records_gps_status_idx on public.attendance_records (tenant_id, gps_verification_status);

-- ---------------------------------------------------------------------------
-- 13.2/13.4 clock_in() gains optional GPS parameters. Reproduces the
-- currently-active function body (20260919090200) in full — every existing
-- check (own-or-manager, terminated-employee, cross-tenant site, shift
-- ownership, already-clocked-in) is unchanged — and adds the server-side
-- geofence decision as new logic, not a replacement of anything.
--
-- CREATE OR REPLACE cannot change a function's parameter list — a
-- different signature creates a second overload rather than replacing the
-- old one, which leaves an ambiguous-call trap for any untyped literal
-- caller (exactly what supabase-js's .rpc() sends). Drop the prior
-- signature explicitly so exactly one clock_in/clock_out exists.

drop function if exists public.clock_in(uuid, uuid, uuid);
drop function if exists public.clock_out(uuid);

create or replace function public.clock_in(
  p_employee_id uuid,
  p_site_id uuid,
  p_shift_id uuid default null,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_accuracy_meters numeric default null,
  p_client_captured_at timestamptz default null,
  p_gps_denied boolean default false,
  p_offline_captured boolean default false,
  p_device_context jsonb default '{}'::jsonb
)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_own boolean;
  v_result public.attendance_records;
  v_geofence public.site_geofences;
  v_status public.gps_verification_status;
  v_reason text;
  v_distance numeric;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  select exists(select 1 from public.employees where id = p_employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_tenant_id)) then
    raise exception 'insufficient_privilege: cannot clock in this employee';
  end if;

  if not public.employee_can_self_serve(p_employee_id) then
    raise exception 'inactive_employee: this employee is terminated or suspended and cannot clock in';
  end if;

  if not exists (select 1 from public.sites where id = p_site_id and tenant_id = v_tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', p_site_id, v_tenant_id;
  end if;

  if p_shift_id is not null and not exists (select 1 from public.shifts where id = p_shift_id and tenant_id = v_tenant_id and employee_id = p_employee_id) then
    raise exception 'not_found: shift % does not belong to this employee in this tenant', p_shift_id;
  end if;

  if exists (select 1 from public.attendance_records where employee_id = p_employee_id and clock_in_at is not null and clock_out_at is null) then
    raise exception 'already_clocked_in: this employee already has an open attendance record';
  end if;

  -- Server-side geofence decision. A manager clocking in on an employee's
  -- behalf (not v_is_own) never carries device GPS — 'not_applicable', not
  -- a failure, matches 13.4's own enum design.
  select * into v_geofence from public.site_geofences where site_id = p_site_id and enabled;

  if not v_is_own then
    v_status := 'not_applicable';
    v_reason := 'clocked in by a manager on the employee''s behalf; no device location applies';
  elsif p_offline_captured then
    v_status := 'offline_pending';
    v_reason := 'captured while offline; awaiting connectivity to verify';
  elsif p_gps_denied or p_latitude is null or p_longitude is null then
    v_status := 'location_unavailable';
    v_reason := 'device could not produce a location (denied, unsupported, or timed out)';
  elsif not found then
    v_status := 'pending_verification';
    v_reason := 'no geofence is configured for this site yet';
  elsif p_accuracy_meters is not null and p_accuracy_meters > v_geofence.accuracy_threshold_meters then
    v_status := 'low_accuracy';
    v_reason := format('reported accuracy %sm exceeds the site''s %sm threshold', p_accuracy_meters, v_geofence.accuracy_threshold_meters);
  else
    v_distance := public.gps_distance_meters(p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude);
    if v_distance <= v_geofence.radius_meters then
      v_status := 'verified';
      v_reason := format('%sm from site center, within the %sm geofence', round(v_distance), v_geofence.radius_meters);
    else
      v_status := 'outside_geofence';
      v_reason := format('%sm from site center, outside the %sm geofence', round(v_distance), v_geofence.radius_meters);
    end if;
  end if;

  insert into public.attendance_records (tenant_id, shift_id, site_id, employee_id, status, clock_in_at, recorded_by, gps_verification_status)
  values (v_tenant_id, p_shift_id, p_site_id, p_employee_id, 'unconfirmed', now(), auth.uid(), v_status)
  returning * into v_result;

  -- late/present status + late_minutes is computed here, from the linked
  -- shift + attendance policy — unchanged from the pre-GPS clock_in, just
  -- preserved rather than dropped during this reproduction.
  select * into v_result from public.compute_attendance_metrics(v_result.id);

  insert into public.attendance_location_events (
    tenant_id, attendance_record_id, employee_id, site_id, event_type,
    latitude, longitude, accuracy_meters, client_captured_at,
    distance_meters, geofence_radius_meters, verification_status, verification_reason, device_context
  ) values (
    v_tenant_id, v_result.id, p_employee_id, p_site_id, 'clock_in',
    p_latitude, p_longitude, p_accuracy_meters, p_client_captured_at,
    v_distance, v_geofence.radius_meters, v_status, v_reason, coalesce(p_device_context, '{}'::jsonb)
  );

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'attendance_clock_in', 'attendance_records', v_result.id, null,
    jsonb_build_object('clock_in_at', v_result.clock_in_at, 'status', v_result.status, 'site_id', p_site_id, 'gps_verification_status', v_status));

  return v_result;
end;
$$;

revoke execute on function public.clock_in(uuid, uuid, uuid, numeric, numeric, numeric, timestamptz, boolean, boolean, jsonb) from public, anon;
grant execute on function public.clock_in(uuid, uuid, uuid, numeric, numeric, numeric, timestamptz, boolean, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- clock_out() gains the same optional GPS parameters, same evidence
-- recording, no change to any of its existing checks.

create or replace function public.clock_out(
  p_attendance_record_id uuid,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_accuracy_meters numeric default null,
  p_client_captured_at timestamptz default null,
  p_gps_denied boolean default false,
  p_offline_captured boolean default false,
  p_device_context jsonb default '{}'::jsonb
)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
  v_geofence public.site_geofences;
  v_status public.gps_verification_status;
  v_reason text;
  v_distance numeric;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id for update;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot clock out this attendance record';
  end if;

  if v_record.clock_in_at is null then
    raise exception 'invalid_sequence: cannot clock out before clocking in';
  end if;
  if v_record.clock_out_at is not null then
    raise exception 'invalid_sequence: already clocked out';
  end if;
  if exists (select 1 from public.attendance_breaks where attendance_record_id = p_attendance_record_id and break_end is null) then
    raise exception 'invalid_sequence: end the open break before clocking out';
  end if;

  select * into v_geofence from public.site_geofences where site_id = v_record.site_id and enabled;

  if not v_is_own then
    v_status := 'not_applicable';
    v_reason := 'clocked out by a manager on the employee''s behalf; no device location applies';
  elsif p_offline_captured then
    v_status := 'offline_pending';
    v_reason := 'captured while offline; awaiting connectivity to verify';
  elsif p_gps_denied or p_latitude is null or p_longitude is null then
    v_status := 'location_unavailable';
    v_reason := 'device could not produce a location (denied, unsupported, or timed out)';
  elsif not found then
    v_status := 'pending_verification';
    v_reason := 'no geofence is configured for this site yet';
  elsif p_accuracy_meters is not null and p_accuracy_meters > v_geofence.accuracy_threshold_meters then
    v_status := 'low_accuracy';
    v_reason := format('reported accuracy %sm exceeds the site''s %sm threshold', p_accuracy_meters, v_geofence.accuracy_threshold_meters);
  else
    v_distance := public.gps_distance_meters(p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude);
    if v_distance <= v_geofence.radius_meters then
      v_status := 'verified';
      v_reason := format('%sm from site center, within the %sm geofence', round(v_distance), v_geofence.radius_meters);
    else
      v_status := 'outside_geofence';
      v_reason := format('%sm from site center, outside the %sm geofence', round(v_distance), v_geofence.radius_meters);
    end if;
  end if;

  if p_latitude is not null or p_gps_denied or p_offline_captured then
    insert into public.attendance_location_events (
      tenant_id, attendance_record_id, employee_id, site_id, event_type,
      latitude, longitude, accuracy_meters, client_captured_at,
      distance_meters, geofence_radius_meters, verification_status, verification_reason, device_context
    ) values (
      v_record.tenant_id, v_record.id, v_record.employee_id, v_record.site_id, 'clock_out',
      p_latitude, p_longitude, p_accuracy_meters, p_client_captured_at,
      v_distance, v_geofence.radius_meters, v_status, v_reason, coalesce(p_device_context, '{}'::jsonb)
    );
  end if;

  update public.attendance_records set clock_out_at = now() where id = p_attendance_record_id;

  select * into v_record from public.compute_attendance_metrics(p_attendance_record_id);

  perform public.write_audit_log(v_record.tenant_id, auth.uid(), 'attendance_clock_out', 'attendance_records', v_record.id, null,
    jsonb_build_object('clock_out_at', v_record.clock_out_at, 'worked_minutes', v_record.worked_minutes));

  return v_record;
end;
$$;

revoke execute on function public.clock_out(uuid, numeric, numeric, numeric, timestamptz, boolean, boolean, jsonb) from public, anon;
grant execute on function public.clock_out(uuid, numeric, numeric, numeric, timestamptz, boolean, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Manual exception workflow RPCs.

create or replace function public.request_attendance_location_exception(
  p_attendance_record_id uuid,
  p_reason text
)
returns public.attendance_location_exceptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance_records;
  v_is_own boolean;
  v_result public.attendance_location_exceptions;
begin
  select * into v_record from public.attendance_records where id = p_attendance_record_id;
  if not found then
    raise exception 'not_found: no attendance record %', p_attendance_record_id;
  end if;

  select exists(select 1 from public.employees where id = v_record.employee_id and profile_id = auth.uid()) into v_is_own;
  if not (v_is_own or public.can_manage_operations(v_record.tenant_id)) then
    raise exception 'insufficient_privilege: cannot request an exception for this attendance record';
  end if;

  if v_record.gps_verification_status not in ('outside_geofence', 'location_unavailable', 'low_accuracy') then
    raise exception 'invalid_request: this attendance record does not have a failed GPS verification to explain (status: %)', v_record.gps_verification_status;
  end if;

  insert into public.attendance_location_exceptions (tenant_id, attendance_record_id, employee_id, reason)
  values (v_record.tenant_id, p_attendance_record_id, v_record.employee_id, p_reason)
  returning * into v_result;

  perform public.write_audit_log(v_record.tenant_id, auth.uid(), 'attendance_location_exception_requested', 'attendance_location_exceptions', v_result.id, null, jsonb_build_object('reason', p_reason));

  return v_result;
end;
$$;

revoke execute on function public.request_attendance_location_exception(uuid, text) from public, anon;
grant execute on function public.request_attendance_location_exception(uuid, text) to authenticated;

create or replace function public.decide_attendance_location_exception(
  p_exception_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns public.attendance_location_exceptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exception public.attendance_location_exceptions;
  v_result public.attendance_location_exceptions;
begin
  select * into v_exception from public.attendance_location_exceptions where id = p_exception_id for update;
  if not found then
    raise exception 'not_found: no attendance location exception %', p_exception_id;
  end if;

  if not public.can_manage_operations(v_exception.tenant_id) then
    raise exception 'insufficient_privilege: cannot decide attendance location exceptions for this tenant';
  end if;

  if exists (select 1 from public.employees where id = v_exception.employee_id and profile_id = auth.uid()) and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot decide your own attendance location exception';
  end if;

  if v_exception.status <> 'pending' then
    raise exception 'invalid_transition: only a pending exception can be decided (current status: %)', v_exception.status;
  end if;

  update public.attendance_location_exceptions
    set status = case when p_approve then 'approved' else 'rejected' end,
        reviewed_by = auth.uid(), reviewed_at = now(), review_notes = p_review_notes
    where id = p_exception_id
    returning * into v_result;

  perform public.write_audit_log(v_exception.tenant_id, auth.uid(), 'attendance_location_exception_decided', 'attendance_location_exceptions', p_exception_id,
    jsonb_build_object('status', 'pending'), jsonb_build_object('status', v_result.status, 'review_notes', p_review_notes));

  return v_result;
end;
$$;

revoke execute on function public.decide_attendance_location_exception(uuid, boolean, text) from public, anon;
grant execute on function public.decide_attendance_location_exception(uuid, boolean, text) to authenticated;
