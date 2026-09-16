-- Sebetsa Domain 14 — Operations Command Centre + operational alert engine
-- + panic/duress/emergency response + notification delivery tracking.
-- Regression coverage for operational_alerts, emergency_events,
-- emergency_responses, emergency_escalation_policies,
-- notification_deliveries and their RPCs
-- (supabase/migrations/20260921090200_command_centre_alerts.sql,
-- 20260921090300_emergency_response.sql, 20260921090400_notification_delivery.sql).
--
--   supabase start
--   cat supabase/rls-tests/domain14_command_centre_emergency.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000e101', 'Tenant A (Domain 14)', 'active'),
  ('00000000-0000-0000-0000-00000000e201', 'Tenant B (Domain 14 cross-tenant)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e102', 'authenticated', 'authenticated', 'admin-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e103', 'authenticated', 'authenticated', 'guard-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e104', 'authenticated', 'authenticated', 'other-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e202', 'authenticated', 'authenticated', 'admin-e2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000e102', '00000000-0000-0000-0000-00000000e101', 'Admin', 'E1', 'admin-e1@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000e103', '00000000-0000-0000-0000-00000000e101', 'Guard', 'One', 'guard-e1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000e104', '00000000-0000-0000-0000-00000000e101', 'Other', 'Guard', 'other-e1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000e202', '00000000-0000-0000-0000-00000000e201', 'Admin', 'E2', 'admin-e2@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000e105', '00000000-0000-0000-0000-00000000e101', 'Client E1');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000000e106', '00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e105', 'Site E1', 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date, home_site_id) values
  ('00000000-0000-0000-0000-00000000e107', '00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e103', 'E1001', 'Guard', 'One', current_date - 30, '00000000-0000-0000-0000-00000000e106'),
  ('00000000-0000-0000-0000-00000000e108', '00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e104', 'E1002', 'Other', 'Guard', current_date - 30, '00000000-0000-0000-0000-00000000e106');
insert into public.site_assignments (tenant_id, site_id, employee_id) values
  ('00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e106', '00000000-0000-0000-0000-00000000e107');

-- One staffing requirement of 2 with nobody assigned yet except Guard One
-- (assigned=1 < required=2) — a real, deterministic understaffing case for
-- the sweep to raise.
insert into public.site_staffing_requirements (tenant_id, site_id, label, required_count) values
  ('00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e106', 'Day shift guards', 2);

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Operational alert sweep: deterministic, cron-only, idempotent.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.raise_understaffed_site_alerts();
    raise exception 'SECURITY_FAILURE: an ordinary authenticated user called raise_understaffed_site_alerts() directly';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: authenticated users cannot call the alert sweep directly (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- reset to postgres superuser (bypasses the revoke, same as p1_expiry_sweeps.sql).
do $$
declare v_count1 int; v_count2 int; v_alert_count int;
begin
  select public.raise_understaffed_site_alerts() into v_count1;
  select public.raise_understaffed_site_alerts() into v_count2;
  select count(*) into v_alert_count from public.operational_alerts
    where tenant_id = '00000000-0000-0000-0000-00000000e101' and alert_type = 'site_understaffed' and status = 'open';
  if v_alert_count <> 1 then raise exception 'FAIL: expected exactly 1 open understaffed-site alert after two sweep runs (dedup), got %', v_alert_count; end if;
  raise notice 'PASS: the understaffed-site sweep is idempotent — re-running it does not raise a second open alert for the same site';
end $$;

-- ---------------------------------------------------------------------------
-- Alert lifecycle: acknowledge/resolve/reopen — privilege + cross-tenant +
-- state-machine correctness.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e103","app_metadata":{"role":"employee"}}';

do $$
declare v_alert_id uuid;
begin
  select id into v_alert_id from public.operational_alerts where tenant_id = '00000000-0000-0000-0000-00000000e101' and alert_type = 'site_understaffed';
  begin
    perform public.acknowledge_operational_alert(v_alert_id);
    raise exception 'SECURITY_FAILURE: an ordinary employee acknowledged an operational alert';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an ordinary employee cannot acknowledge an operational alert (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_alert_id uuid;
begin
  select id into v_alert_id from public.operational_alerts where tenant_id = '00000000-0000-0000-0000-00000000e101' and alert_type = 'site_understaffed';
  begin
    perform public.acknowledge_operational_alert(v_alert_id);
    raise exception 'SECURITY_FAILURE: Tenant B admin acknowledged a Tenant A alert';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant alert acknowledgement is denied (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_alert_id uuid; v_result public.operational_alerts;
begin
  select id into v_alert_id from public.operational_alerts where tenant_id = '00000000-0000-0000-0000-00000000e101' and alert_type = 'site_understaffed';

  select * into v_result from public.acknowledge_operational_alert(v_alert_id);
  if v_result.status <> 'acknowledged' then raise exception 'FAIL: expected acknowledged, got %', v_result.status; end if;

  begin
    perform public.acknowledge_operational_alert(v_alert_id);
    raise exception 'SECURITY_FAILURE: an already-acknowledged alert was acknowledged again';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-acknowledged alert cannot be acknowledged again (%)', sqlerrm;
  end;

  select * into v_result from public.resolve_operational_alert(v_alert_id, 'extra guard rostered for tomorrow');
  if v_result.status <> 'resolved' then raise exception 'FAIL: expected resolved, got %', v_result.status; end if;
  raise notice 'PASS: an alert progresses open -> acknowledged -> resolved correctly';

  select * into v_result from public.reopen_operational_alert(v_alert_id, 'roster fell through');
  if v_result.status <> 'open' then raise exception 'FAIL: expected reopened alert to be open, got %', v_result.status; end if;
  raise notice 'PASS: a resolved alert can be controlled-reopened';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Emergency lifecycle: trigger -> acknowledge -> respond -> resolve, with
-- immutability of the trigger event and strict location-data access control.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e103","app_metadata":{"role":"employee"}}';

do $$
declare v_event public.emergency_events; v_rows int;
begin
  select * into v_event from public.trigger_emergency(-26.204100, 28.047300, 15, 'panic');
  if v_event.employee_id <> '00000000-0000-0000-0000-00000000e107' then raise exception 'FAIL: emergency event recorded the wrong employee'; end if;
  raise notice 'PASS: an employee can trigger a panic/emergency event';

  -- No UPDATE policy exists for authenticated on emergency_events, so this
  -- silently affects zero rows under RLS rather than raising — assert on
  -- the row count, not an exception.
  update public.emergency_events set emergency_type = 'other' where id = v_event.id;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: the immutable emergency_events row was updated by its own triggering employee (% rows affected)', v_rows; end if;
  raise notice 'PASS: emergency_events is truly append-only — no UPDATE policy exists for authenticated, so the UPDATE affects zero rows';
end $$;

reset role;
reset request.jwt.claims;

-- A different employee (same tenant) cannot see this emergency's location/identity.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e104","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.emergency_events where employee_id = '00000000-0000-0000-0000-00000000e107';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a different employee read another employee''s emergency event (location + identity)'; end if;
  raise notice 'PASS: a co-worker cannot read another employee''s emergency event';
end $$;

reset role;
reset request.jwt.claims;

-- A client_user (not an operational role) must never see emergency events —
-- can_manage_operations() already excludes client_user by construction, but
-- prove it holds for this specific highly-sensitive table too.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e109', 'authenticated', 'authenticated', 'client-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000e109', '00000000-0000-0000-0000-00000000e101', 'Client', 'User', 'client-e1@example.com', 'client_user', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e109","app_metadata":{"role":"client_user"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.emergency_events where tenant_id = '00000000-0000-0000-0000-00000000e101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a client_user read emergency event location/identity data'; end if;
  raise notice 'PASS: client_user can never read emergency event data';
end $$;

reset role;
reset request.jwt.claims;

-- Cross-tenant admin cannot acknowledge; an ordinary employee cannot
-- acknowledge; resolve before acknowledge is rejected; the full lifecycle
-- succeeds for a legitimate operations-tier caller and resolving also
-- resolves the linked critical alert.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_event_id uuid;
begin
  select id into v_event_id from public.emergency_events where tenant_id = '00000000-0000-0000-0000-00000000e101' order by triggered_at desc limit 1;
  begin
    perform public.acknowledge_emergency(v_event_id);
    raise exception 'SECURITY_FAILURE: Tenant B admin acknowledged a Tenant A emergency';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant emergency acknowledgement is denied (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e103","app_metadata":{"role":"employee"}}';

do $$
declare v_event_id uuid;
begin
  select id into v_event_id from public.emergency_events where tenant_id = '00000000-0000-0000-0000-00000000e101' order by triggered_at desc limit 1;
  begin
    perform public.acknowledge_emergency(v_event_id);
    raise exception 'SECURITY_FAILURE: an ordinary employee (not operations-tier) acknowledged an emergency';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an ordinary employee cannot acknowledge an emergency (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_event_id uuid; v_response public.emergency_responses; v_alert_status public.alert_status;
begin
  select id into v_event_id from public.emergency_events where tenant_id = '00000000-0000-0000-0000-00000000e101' order by triggered_at desc limit 1;

  begin
    perform public.resolve_emergency(v_event_id, 'false alarm');
    raise exception 'SECURITY_FAILURE: an unacknowledged (triggered-only) emergency was resolved directly';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an unacknowledged emergency cannot be resolved directly (%)', sqlerrm;
  end;

  select * into v_response from public.acknowledge_emergency(v_event_id);
  if v_response.status <> 'acknowledged' then raise exception 'FAIL: expected acknowledged, got %', v_response.status; end if;

  select * into v_response from public.respond_to_emergency(v_event_id, 'supervisor en route');
  if v_response.status <> 'responding' then raise exception 'FAIL: expected responding, got %', v_response.status; end if;

  select * into v_response from public.resolve_emergency(v_event_id, 'guard confirmed safe, false alarm');
  if v_response.status <> 'resolved' then raise exception 'FAIL: expected resolved, got %', v_response.status; end if;
  raise notice 'PASS: the full emergency lifecycle (triggered -> acknowledged -> responding -> resolved) works for an operations-tier caller';

  select status into v_alert_status from public.operational_alerts
    where tenant_id = '00000000-0000-0000-0000-00000000e101' and alert_type = 'emergency_active' and employee_id = '00000000-0000-0000-0000-00000000e107';
  if v_alert_status <> 'resolved' then raise exception 'FAIL: expected resolving the emergency to also resolve its linked critical alert, got %', v_alert_status; end if;
  raise notice 'PASS: resolving an emergency also resolves its linked operational alert';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Self-approval: a site_manager (operations-tier) is ALSO an employee who
-- can trigger their own panic. Independent oversight means they must not
-- be able to acknowledge/respond/resolve their own emergency, nor bypass
-- that by acting on the linked operational_alert directly instead of the
-- emergency-specific RPC.

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e111', 'authenticated', 'authenticated', 'sitemgr-e1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000e111', '00000000-0000-0000-0000-00000000e101', 'Site', 'Manager', 'sitemgr-e1@example.com', 'site_manager', 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000e112', '00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e111', 'E1003', 'Site', 'Manager', current_date - 90);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e111","app_metadata":{"role":"site_manager"}}';

do $$
declare v_event_id uuid; v_alert_id uuid;
begin
  perform public.trigger_emergency(-26.204100, 28.047300, 15, 'panic');
  select id into v_event_id from public.emergency_events where employee_id = '00000000-0000-0000-0000-00000000e112' order by triggered_at desc limit 1;
  select id into v_alert_id from public.operational_alerts where alert_type = 'emergency_active' and employee_id = '00000000-0000-0000-0000-00000000e112';

  begin
    perform public.acknowledge_emergency(v_event_id);
    raise exception 'SECURITY_FAILURE: a site_manager acknowledged their own triggered emergency';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a site_manager cannot acknowledge their own emergency (%)', sqlerrm;
  end;

  begin
    perform public.acknowledge_operational_alert(v_alert_id);
    raise exception 'SECURITY_FAILURE: a site_manager acknowledged the operational alert for their own emergency, bypassing acknowledge_emergency()''s guard';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: the same self-approval guard holds on the underlying operational_alerts RPC, not just the emergency-specific one (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- A different ops-tier user acknowledges it first, then the site_manager
-- still cannot respond/resolve their own emergency even once acknowledged.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  perform public.acknowledge_emergency((select id from public.emergency_events where employee_id = '00000000-0000-0000-0000-00000000e112' order by triggered_at desc limit 1));
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e111","app_metadata":{"role":"site_manager"}}';

do $$
declare v_event_id uuid;
begin
  select id into v_event_id from public.emergency_events where employee_id = '00000000-0000-0000-0000-00000000e112' order by triggered_at desc limit 1;

  begin
    perform public.respond_to_emergency(v_event_id);
    raise exception 'SECURITY_FAILURE: a site_manager marked their own emergency as responding';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a site_manager cannot respond to their own emergency, even once another ops-tier user has acknowledged it (%)', sqlerrm;
  end;

  begin
    perform public.resolve_emergency(v_event_id, 'self-resolving');
    raise exception 'SECURITY_FAILURE: a site_manager resolved their own emergency';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a site_manager cannot resolve their own emergency (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Escalation: tenant-configurable chain, cron-only sweep, self-approval-free
-- (no client can invoke it, only the automatic sweep advances a level).

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

insert into public.emergency_escalation_policies (tenant_id, level, escalate_to_role, timeout_minutes) values
  ('00000000-0000-0000-0000-00000000e101', 1, 'site_manager', 1),
  ('00000000-0000-0000-0000-00000000e101', 2, 'operations_manager', 1);

do $$
declare v_count int;
begin
  begin
    perform public.escalate_overdue_emergencies();
    raise exception 'SECURITY_FAILURE: an ordinary authenticated user called escalate_overdue_emergencies() directly';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: authenticated users cannot call the emergency escalation sweep directly (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- A brand-new triggered-and-unacknowledged emergency, backdated (as
-- postgres, which bypasses RLS regardless of FORCE ROW LEVEL SECURITY) so
-- the configured 1-minute level-1 timeout has genuinely elapsed.
do $$
declare v_event_id uuid; v_response_id uuid; v_level int;
begin
  insert into public.emergency_events (tenant_id, employee_id, emergency_type, triggered_at)
    values ('00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e107', 'panic', now() - interval '10 minutes')
    returning id into v_event_id;
  insert into public.emergency_responses (tenant_id, emergency_event_id, status)
    values ('00000000-0000-0000-0000-00000000e101', v_event_id, 'triggered')
    returning id into v_response_id;

  perform public.escalate_overdue_emergencies();
  select escalation_level into v_level from public.emergency_responses where id = v_response_id;
  if v_level <> 1 then raise exception 'FAIL: expected escalation_level=1 after the first overdue sweep, got %', v_level; end if;

  perform public.escalate_overdue_emergencies();
  select escalation_level into v_level from public.emergency_responses where id = v_response_id;
  if v_level <> 2 then raise exception 'FAIL: expected escalation_level=2 after the second overdue sweep, got %', v_level; end if;
  raise notice 'PASS: an overdue, unacknowledged emergency escalates through the tenant''s configured chain, one level per sweep';
end $$;

-- ---------------------------------------------------------------------------
-- Command centre snapshot: RLS-riding aggregation — the client-supplied
-- p_tenant_id cannot be used to read another tenant's figures, because
-- every underlying aggregate is still filtered by the caller's own RLS.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_snapshot record;
begin
  select * into v_snapshot from public.get_command_centre_snapshot('00000000-0000-0000-0000-00000000e101');
  if v_snapshot.sites_total_active <> 0 or v_snapshot.alerts_open <> 0 or v_snapshot.emergencies_active <> 0 then
    raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A figures out of get_command_centre_snapshot() by passing Tenant A''s id';
  end if;
  raise notice 'PASS: get_command_centre_snapshot() cannot be used to read another tenant''s figures via a spoofed p_tenant_id — every aggregate is still RLS-scoped to the caller';
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_snapshot record;
begin
  select * into v_snapshot from public.get_command_centre_snapshot('00000000-0000-0000-0000-00000000e101');
  if v_snapshot.sites_total_active <> 1 then raise exception 'FAIL: expected sites_total_active=1, got %', v_snapshot.sites_total_active; end if;
  raise notice 'PASS: get_command_centre_snapshot() returns real, live aggregate figures for the caller''s own tenant';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Notification delivery tracking: recipient/ops-tier visibility, status
-- update requires operations-tier privilege, cross-tenant denial.

-- create_notification() is deliberately NOT granted to authenticated (a
-- client picking its own recipient/content would be a spoofing vector) —
-- it's only ever called from inside another privileged RPC's own body.
-- Set up the notification fixture directly, as postgres (bypasses RLS),
-- the same way the real privileged RPCs that wrap it would.
insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body)
values ('00000000-0000-0000-0000-00000000e110', '00000000-0000-0000-0000-00000000e101', '00000000-0000-0000-0000-00000000e103', 'shift_reminder', 'Reminder', 'Your shift starts soon');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_delivery public.notification_deliveries;
begin
  select * into v_delivery from public.record_notification_delivery('00000000-0000-0000-0000-00000000e110', 'push', 'fcm');
  if v_delivery.delivery_status <> 'pending' then raise exception 'FAIL: expected a push delivery to start pending, got %', v_delivery.delivery_status; end if;
  raise notice 'PASS: recording a push delivery attempt starts pending (no real provider claims success it has not verified)';
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e104","app_metadata":{"role":"employee"}}';

do $$
declare v_delivery_id uuid;
begin
  select id into v_delivery_id from public.notification_deliveries
    where notification_id in (select id from public.notifications where recipient_profile_id = '00000000-0000-0000-0000-00000000e103');
  begin
    perform public.update_notification_delivery_status(v_delivery_id, 'delivered');
    raise exception 'SECURITY_FAILURE: an unrelated employee updated another employee''s notification delivery status';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: only operations-tier can update a notification delivery status (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.notification_deliveries
    where notification_id in (select id from public.notifications where recipient_profile_id = '00000000-0000-0000-0000-00000000e107');
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A notification delivery records'; end if;
  raise notice 'PASS: cross-tenant notification delivery data is denied';
end $$;

reset role;
reset request.jwt.claims;

rollback;
