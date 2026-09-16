-- Sebetsa Domain 13 — GPS-verified field presence + guard tours.
-- Regression coverage for site_geofences, attendance_location_events,
-- attendance_location_exceptions, checkpoints, patrol_routes,
-- patrol_route_checkpoints, patrol_runs, patrol_checkpoint_scans and the
-- clock_in/clock_out/start_patrol/scan_checkpoint/complete_patrol RPCs
-- (supabase/migrations/20260921090000_gps_field_presence.sql,
-- 20260921090100_guard_tours.sql).
--
--   supabase start
--   cat supabase/rls-tests/domain13_gps_guard_tours.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000d101', 'Tenant A (Domain 13)', 'active'),
  ('00000000-0000-0000-0000-00000000d201', 'Tenant B (Domain 13 cross-tenant)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d102', 'authenticated', 'authenticated', 'admin-d1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d103', 'authenticated', 'authenticated', 'guard-d1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d104', 'authenticated', 'authenticated', 'other-d1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d202', 'authenticated', 'authenticated', 'admin-d2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000d102', '00000000-0000-0000-0000-00000000d101', 'Admin', 'D1', 'admin-d1@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000d103', '00000000-0000-0000-0000-00000000d101', 'Guard', 'One', 'guard-d1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000d104', '00000000-0000-0000-0000-00000000d101', 'Other', 'Guard', 'other-d1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000d202', '00000000-0000-0000-0000-00000000d201', 'Admin', 'D2', 'admin-d2@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d102","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000d105', '00000000-0000-0000-0000-00000000d101', 'Client D1');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000000d106', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d105', 'Site D1', 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000d107', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d103', 'D1001', 'Guard', 'One', current_date - 30),
  ('00000000-0000-0000-0000-00000000d108', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d104', 'D1002', 'Other', 'Guard', current_date - 30);
insert into public.site_assignments (tenant_id, site_id, employee_id) values ('00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d106', '00000000-0000-0000-0000-00000000d107');

-- Site D1 at -26.204100,28.047300 (Johannesburg-ish), 100m radius.
insert into public.site_geofences (tenant_id, site_id, latitude, longitude, radius_meters, configured_by)
values ('00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d106', -26.204100, 28.047300, 100, '00000000-0000-0000-0000-00000000d102');

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- GPS clock-in: inside vs outside the geofence, server-computed.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d103","app_metadata":{"role":"employee"}}';

do $$
declare v_record public.attendance_records;
begin
  -- ~11m from the geofence center — well inside a 100m radius.
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000000d107', '00000000-0000-0000-0000-00000000d106', null, -26.204200, 28.047300, 15);
  if v_record.gps_verification_status <> 'verified' then raise exception 'FAIL: expected verified inside the geofence, got %', v_record.gps_verification_status; end if;
  raise notice 'PASS: clock_in inside the geofence is server-verified';
  perform public.clock_out(v_record.id, -26.204200, 28.047300, 15);
end $$;

do $$
declare v_record public.attendance_records; v_evidence_count int;
begin
  -- ~1.1km away — well outside a 100m radius. Attendance is still recorded
  -- (not silently converted to verified, but not blocked either — a
  -- supervisor exception exists for exactly this).
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000000d107', '00000000-0000-0000-0000-00000000d106', null, -26.214100, 28.047300, 15);
  if v_record.gps_verification_status <> 'outside_geofence' then raise exception 'SECURITY_FAILURE: a clock-in 1.1km from the site was recorded as %, not outside_geofence — the server did not compute the distance', v_record.gps_verification_status; end if;
  raise notice 'PASS: clock_in outside the geofence is correctly flagged, not silently accepted';

  select count(*) into v_evidence_count from public.attendance_location_events where attendance_record_id = v_record.id;
  if v_evidence_count <> 1 then raise exception 'FAIL: expected exactly 1 location evidence row, got %', v_evidence_count; end if;

  perform public.clock_out(v_record.id);
end $$;

do $$
declare v_record public.attendance_records;
begin
  -- device denies location entirely.
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000000d107', '00000000-0000-0000-0000-00000000d106', null, null, null, null, null, true);
  if v_record.gps_verification_status <> 'location_unavailable' then raise exception 'FAIL: expected location_unavailable, got %', v_record.gps_verification_status; end if;
  raise notice 'PASS: a denied/unavailable GPS read is recorded as location_unavailable, never silently verified';
  perform public.clock_out(v_record.id);
end $$;

-- The frontend cannot claim verification itself — is_within_geofence is
-- not a parameter clock_in accepts at all; confirmed by the three
-- assertions above, each driven only by raw lat/lng/accuracy.

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Manual exception workflow: request, self-approval denied, cross-tenant
-- denied, legitimate approval succeeds.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d103","app_metadata":{"role":"employee"}}';

do $$
declare v_record public.attendance_records; v_exception public.attendance_location_exceptions;
begin
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000000d107', '00000000-0000-0000-0000-00000000d106', null, -26.214100, 28.047300, 15);
  select * into v_exception from public.request_attendance_location_exception(v_record.id, 'My phone GPS was inaccurate near the parking structure');
  perform public.clock_out(v_record.id);

  begin
    perform public.decide_attendance_location_exception(v_exception.id, true, 'self-approving');
    raise exception 'SECURITY_FAILURE: an employee approved their own GPS exception';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an employee cannot decide their own GPS exception (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_exception_id uuid;
begin
  select id into v_exception_id from public.attendance_location_exceptions where tenant_id = '00000000-0000-0000-0000-00000000d101' limit 1;
  begin
    perform public.decide_attendance_location_exception(v_exception_id, true);
    raise exception 'SECURITY_FAILURE: Tenant B admin decided a Tenant A GPS exception';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant GPS exception decision is denied (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_exception_id uuid; v_result public.attendance_location_exceptions;
begin
  select id into v_exception_id from public.attendance_location_exceptions where tenant_id = '00000000-0000-0000-0000-00000000d101' limit 1;
  select * into v_result from public.decide_attendance_location_exception(v_exception_id, true, 'confirmed with the client, parking structure blocks GPS');
  if v_result.status <> 'approved' then raise exception 'FAIL: expected approved, got %', v_result.status; end if;
  raise notice 'PASS: a legitimate (non-self) GPS exception decision succeeds';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Location evidence privacy: employee sees only their own; a different
-- employee (even same tenant) cannot; cross-tenant admin cannot.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d104","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.attendance_location_events where employee_id = '00000000-0000-0000-0000-00000000d107';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a different employee read another employee''s GPS evidence'; end if;
  raise notice 'PASS: an employee cannot read a different employee''s location evidence';
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.attendance_location_events where tenant_id = '00000000-0000-0000-0000-00000000d101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A GPS evidence'; end if;
  raise notice 'PASS: cross-tenant location evidence is denied';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Guard tours: route config, assignment enforcement, sequence/duplicate
-- validation, completion.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d102","app_metadata":{"role":"organization_administrator"}}';

insert into public.checkpoints (id, tenant_id, site_id, code, name) values
  ('00000000-0000-0000-0000-00000000d109', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d106', 'CP-A', 'Main Gate'),
  ('00000000-0000-0000-0000-00000000d10a', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d106', 'CP-B', 'Loading Bay');
insert into public.patrol_routes (id, tenant_id, site_id, name, allowed_start_window_minutes, completion_threshold_pct) values
  ('00000000-0000-0000-0000-00000000d10b', '00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000d106', 'Night Patrol', 120, 100);
insert into public.patrol_route_checkpoints (patrol_route_id, checkpoint_id, sequence_number, tolerance_window_minutes) values
  ('00000000-0000-0000-0000-00000000d10b', '00000000-0000-0000-0000-00000000d109', 1, 30),
  ('00000000-0000-0000-0000-00000000d10b', '00000000-0000-0000-0000-00000000d10a', 2, 30);

reset role;
reset request.jwt.claims;

-- Not-assigned employee cannot start a patrol at a site they aren't posted to.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d104","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.start_patrol('00000000-0000-0000-0000-00000000d10b');
    raise exception 'SECURITY_FAILURE: an unassigned employee started a patrol at a site they are not posted to';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an unassigned employee cannot start a patrol here (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d103","app_metadata":{"role":"employee"}}';

do $$
declare
  v_run public.patrol_runs;
  -- scan_checkpoint() returns a two-composite-column row (scan, run);
  -- plpgsql cannot INTO two separate record-typed variables from one row,
  -- so capture the whole row untyped and dot into each composite column.
  v_row record;
begin
  select * into v_run from public.start_patrol('00000000-0000-0000-0000-00000000d10b');

  -- Wrong order: scanning CP-B before CP-A.
  select * into v_row from public.scan_checkpoint(v_run.id, 'CP-B');
  if (v_row.scan).verification_result <> 'wrong_sequence' then raise exception 'FAIL: expected wrong_sequence, got %', (v_row.scan).verification_result; end if;
  raise notice 'PASS: scanning out of sequence is flagged, not silently accepted';

  -- Correct: CP-A.
  select * into v_row from public.scan_checkpoint(v_run.id, 'CP-A');
  if (v_row.scan).verification_result <> 'valid' then raise exception 'FAIL: expected valid, got %', (v_row.scan).verification_result; end if;

  -- Duplicate: CP-A again.
  select * into v_row from public.scan_checkpoint(v_run.id, 'CP-A');
  if (v_row.scan).verification_result <> 'duplicate' then raise exception 'FAIL: expected duplicate, got %', (v_row.scan).verification_result; end if;
  raise notice 'PASS: re-scanning the same checkpoint is flagged as a duplicate';

  -- Unknown checkpoint code.
  select * into v_row from public.scan_checkpoint(v_run.id, 'DOES-NOT-EXIST');
  if (v_row.scan).verification_result <> 'invalid_checkpoint' then raise exception 'FAIL: expected invalid_checkpoint, got %', (v_row.scan).verification_result; end if;

  -- Correct: CP-B (the real 2nd checkpoint).
  select * into v_row from public.scan_checkpoint(v_run.id, 'CP-B');
  if (v_row.scan).verification_result <> 'valid' then raise exception 'FAIL: expected valid for CP-B, got %', (v_row.scan).verification_result; end if;
  if (v_row.run).scanned_checkpoint_count <> 2 then raise exception 'FAIL: expected scanned_checkpoint_count=2, got %', (v_row.run).scanned_checkpoint_count; end if;

  perform public.complete_patrol(v_run.id);
end $$;

do $$
declare v_status public.patrol_run_status;
begin
  select status into v_status from public.patrol_runs where patrol_route_id = '00000000-0000-0000-0000-00000000d10b' order by started_at desc limit 1;
  if v_status <> 'completed' then raise exception 'FAIL: expected completed (2/2 checkpoints, 100%% threshold), got %', v_status; end if;
  raise notice 'PASS: a fully-scanned patrol completes correctly';
end $$;

-- Cannot start a second patrol while one is already in progress.
do $$
begin
  perform public.start_patrol('00000000-0000-0000-0000-00000000d10b');
  begin
    perform public.start_patrol('00000000-0000-0000-0000-00000000d10b');
    raise exception 'SECURITY_FAILURE: two simultaneous in-progress patrols were allowed for the same employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cannot start a second patrol while one is already in progress (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Cross-tenant patrol data is denied.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.patrol_runs where tenant_id = '00000000-0000-0000-0000-00000000d101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A patrol runs'; end if;
  select count(*) into v_count from public.checkpoints where tenant_id = '00000000-0000-0000-0000-00000000d101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A checkpoints'; end if;
  raise notice 'PASS: cross-tenant patrol/checkpoint data is denied';
end $$;

reset role;
reset request.jwt.claims;

-- Terminated employee cannot start a patrol.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d102","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  perform public.terminate_employee('00000000-0000-0000-0000-00000000d107', current_date);
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000d103","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.start_patrol('00000000-0000-0000-0000-00000000d10b');
    raise exception 'SECURITY_FAILURE: a terminated employee started a patrol';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a terminated employee cannot start a patrol (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
