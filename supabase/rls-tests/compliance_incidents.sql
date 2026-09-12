-- Sebetsa Phase N — Compliance, Safety & Incident Management: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/compliance_incidents.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000191', 'Org N1', 'active'),
  ('00000000-0000-0000-0000-000000000192', 'Org N2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000001901', 'authenticated', 'authenticated', 'admin-n1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000001902', 'authenticated', 'authenticated', 'site-mgr-n1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000001903', 'authenticated', 'authenticated', 'employee-n1a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000001904', 'authenticated', 'authenticated', 'employee-n1b@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000001905', 'authenticated', 'authenticated', 'admin-n2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000001901', '00000000-0000-0000-0000-000000000191', 'Admin', 'N1', 'admin-n1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000000191', 'Site', 'MgrN1', 'site-mgr-n1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000001903', '00000000-0000-0000-0000-000000000191', 'Emp', 'N1A', 'employee-n1a@example.com', 'active'),
  ('00000000-0000-0000-0000-000000001904', '00000000-0000-0000-0000-000000000191', 'Emp', 'N1B', 'employee-n1b@example.com', 'active'),
  ('00000000-0000-0000-0000-000000001905', '00000000-0000-0000-0000-000000000192', 'Admin', 'N2', 'admin-n2@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003901', '00000000-0000-0000-0000-000000000191', 'Client N1');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004901', '00000000-0000-0000-0000-000000000191', '00000000-0000-0000-0000-000000003901', 'Site N1');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_status) values
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-000000000191', '00000000-0000-0000-0000-000000001903', 'EMP-N1A', 'Emp', 'N1A', 'active'),
  ('00000000-0000-0000-0000-000000005902', '00000000-0000-0000-0000-000000000191', '00000000-0000-0000-0000-000000001904', 'EMP-N1B', 'Emp', 'N1B', 'active');

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003902', '00000000-0000-0000-0000-000000000192', 'Client N2');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004902', '00000000-0000-0000-0000-000000000192', '00000000-0000-0000-0000-000000003902', 'Site N2');

-- ---------------------------------------------------------------------------
-- report_incident(): employee self-service reporting, server-derived actor.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001903","app_metadata":{"role":"employee"}}';

do $$
declare v_id uuid; v_reported_by uuid; v_ref text;
begin
  select id, reported_by, reference_number into v_id, v_reported_by, v_ref
  from public.report_incident(
    '00000000-0000-0000-0000-000000000191', 'workplace_safety', 'high', now(), 'Slip on wet floor',
    '00000000-0000-0000-0000-000000004901', null
  );
  if v_reported_by <> '00000000-0000-0000-0000-000000001903' then
    raise exception 'FAIL: reported_by not server-derived to caller';
  end if;
  if v_ref is null or v_ref not like 'INC-%' then
    raise exception 'FAIL: reference_number not generated, got %', v_ref;
  end if;
  raise notice 'PASS: employee can report an incident, reported_by/reference_number server-derived (%, %)', v_id, v_ref;
end $$;

do $$
begin
  begin
    perform public.report_incident('00000000-0000-0000-0000-000000000192', 'workplace_safety', 'low', now(), 'cross tenant', null, null);
    raise exception 'SECURITY_FAILURE: employee reported an incident for a foreign tenant';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant report_incident blocked (%)', sqlerrm;
  end;
end $$;

-- Direct table write must be impossible even for the reporter.
do $$
declare v_rows int;
begin
  begin
    insert into public.incidents (tenant_id, category, severity, occurred_at, description, reported_by)
    values ('00000000-0000-0000-0000-000000000191', 'near_miss', 'low', now(), 'direct insert attempt', auth.uid());
    raise exception 'SECURITY_FAILURE: direct client INSERT into incidents succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: direct client INSERT into incidents blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Lifecycle enforcement + role scoping via the manager tier.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_incident_id uuid;
begin
  select id into v_incident_id from public.incidents where tenant_id = '00000000-0000-0000-0000-000000000191' limit 1;

  -- Illegal jump: reported -> corrective_action (skipping acknowledged/investigating).
  begin
    perform public.transition_incident_status(v_incident_id, 'corrective_action', null);
    raise exception 'SECURITY_FAILURE: illegal incident status jump succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: illegal incident status jump blocked (%)', sqlerrm;
  end;

  perform public.transition_incident_status(v_incident_id, 'acknowledged', null);
  perform public.transition_incident_status(v_incident_id, 'investigating', 'reviewing CCTV');

  perform public.link_incident_employee(v_incident_id, '00000000-0000-0000-0000-000000005901', 'injured');

  perform public.add_incident_action(v_incident_id, 'Place wet floor signage', '00000000-0000-0000-0000-000000001904', current_date + 1);
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents
  where tenant_id = '00000000-0000-0000-0000-000000000191' and status = 'investigating';
  if v_count <> 1 then raise exception 'FAIL: expected 1 incident in investigating status, got %', v_count; end if;
  raise notice 'PASS: valid incident lifecycle transitions applied';
end $$;

-- ---------------------------------------------------------------------------
-- incident_actions: owner self-service completion, manager-only verification.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001904","app_metadata":{"role":"employee"}}';

do $$
declare v_action_id uuid; v_status public.incident_action_status;
begin
  select id into v_action_id from public.incident_actions where owner_profile_id = '00000000-0000-0000-0000-000000001904' limit 1;

  select status into v_status from public.complete_incident_action(v_action_id);
  if v_status <> 'completed' then raise exception 'FAIL: owner could not complete their own action'; end if;
  raise notice 'PASS: action owner can self-complete their assigned action';

  begin
    perform public.verify_incident_action(v_action_id);
    raise exception 'SECURITY_FAILURE: non-manager employee verified an incident action';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: non-manager verify_incident_action blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_action_id uuid; v_status public.incident_action_status;
begin
  select id into v_action_id from public.incident_actions where owner_profile_id = '00000000-0000-0000-0000-000000001904' limit 1;
  select status into v_status from public.verify_incident_action(v_action_id);
  if v_status <> 'verified' then raise exception 'FAIL: manager could not verify a completed action'; end if;
  raise notice 'PASS: manager can verify a completed incident action';
end $$;

-- ---------------------------------------------------------------------------
-- Employee visibility: only own-reported/own-affected/own-owned incidents.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001903","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents where tenant_id = '00000000-0000-0000-0000-000000000191';
  if v_count <> 1 then raise exception 'FAIL: reporter should see their own incident, got % rows', v_count; end if;
  raise notice 'PASS: employee sees their own reported incident (1 row)';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001905","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents where tenant_id = '00000000-0000-0000-0000-000000000191';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: foreign-tenant admin sees % incidents from tenant N1', v_count; end if;
  raise notice 'PASS: cross-tenant incidents invisible (0 rows)';
end $$;

-- ---------------------------------------------------------------------------
-- Compliance requirements + records.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001901","app_metadata":{"role":"organization_administrator"}}';

insert into public.compliance_requirements (id, tenant_id, name, category, applies_to_scope)
values ('00000000-0000-0000-0000-000000006901', '00000000-0000-0000-0000-000000000191', 'Fire Safety Cert', 'safety', 'site');

do $$
declare v_id uuid; v_status public.compliance_status;
begin
  select id, status into v_id, v_status from public.upsert_compliance_record(
    null, '00000000-0000-0000-0000-000000006901', '00000000-0000-0000-0000-000000004901', null, null,
    '00000000-0000-0000-0000-000000001902', current_date + 30, current_date + 365, null, 'initial'
  );
  if v_status <> 'pending' then raise exception 'FAIL: new compliance record should start pending, got %', v_status; end if;
  raise notice 'PASS: compliance record created via upsert_compliance_record (%)', v_id;
end $$;

do $$
begin
  begin
    perform public.upsert_compliance_record(
      null, '00000000-0000-0000-0000-000000006901', '00000000-0000-0000-0000-000000004902', null, null,
      null, current_date, current_date, null, 'cross tenant site'
    );
    raise exception 'SECURITY_FAILURE: compliance record accepted a cross-tenant site reference';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant site reference on compliance record blocked (%)', sqlerrm;
  end;
end $$;

do $$
declare v_id uuid; v_status public.compliance_status; v_verifier uuid;
begin
  select id into v_id from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000006901' limit 1;
  select status, verified_by into v_status, v_verifier from public.verify_compliance_record(v_id, true);
  if v_status <> 'compliant' then raise exception 'FAIL: expected compliant after approval, got %', v_status; end if;
  if v_verifier <> auth.uid() then raise exception 'FAIL: verified_by not server-derived'; end if;
  raise notice 'PASS: verify_compliance_record approves and server-derives verifier';
end $$;

-- Non-manager cannot self-verify.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001902","app_metadata":{"role":"site_manager"}}';

do $$
declare v_id uuid;
begin
  select id into v_id from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000006901' limit 1;
  -- site_manager IS a can_manage_operations() tier member, so this should succeed (re-verification/adjustment).
  perform public.verify_compliance_record(v_id, false);
  raise notice 'PASS: site_manager (operations tier) can also verify compliance records';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000001903","app_metadata":{"role":"employee"}}';

do $$
declare v_id uuid;
begin
  select id into v_id from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000006901' limit 1;
  begin
    perform public.verify_compliance_record(v_id, true);
    raise exception 'SECURITY_FAILURE: plain employee verified a compliance record';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee verify_compliance_record blocked (%)', sqlerrm;
  end;
end $$;

-- Append-only-style audit check.
reset role;
reset request.jwt.claims;
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'incidents' and action = 'incident_reported';
  if v_count < 1 then raise exception 'FAIL: incident report was not audit-logged'; end if;
  raise notice 'PASS: incident reporting is audit-logged';
end $$;

rollback;
