-- Sebetsa security behaviour tests: audit immutability, separation of duties,
-- scope-aware authorization. One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000f0001', 'Org F', 'active'),
  ('00000000-0000-0000-0000-0000000f0002', 'Org G', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(),
       jsonb_build_object('role', u.role), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0101', 'admin-f1@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0102', 'admin-f2@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0103', 'ops-f@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0104', 'regional-f@example.com', 'regional_manager'),
  ('00000000-0000-0000-0000-0000000f0105', 'sitemgr-f@example.com', 'site_manager'),
  ('00000000-0000-0000-0000-0000000f0106', 'employee-f@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0201', 'admin-g@example.com', 'organization_administrator')
) as u(id, email, role);

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
select p.id::uuid, p.tenant::uuid, p.fname, 'Test', p.email, p.role::public.user_role, 'active'
from (values
  ('00000000-0000-0000-0000-0000000f0101', '00000000-0000-0000-0000-0000000f0001', 'AdminOne', 'admin-f1@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0102', '00000000-0000-0000-0000-0000000f0001', 'AdminTwo', 'admin-f2@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0103', '00000000-0000-0000-0000-0000000f0001', 'Ops', 'ops-f@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0104', '00000000-0000-0000-0000-0000000f0001', 'Regional', 'regional-f@example.com', 'regional_manager'),
  ('00000000-0000-0000-0000-0000000f0105', '00000000-0000-0000-0000-0000000f0001', 'SiteMgr', 'sitemgr-f@example.com', 'site_manager'),
  ('00000000-0000-0000-0000-0000000f0106', '00000000-0000-0000-0000-0000000f0001', 'Emp', 'employee-f@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0201', '00000000-0000-0000-0000-0000000f0002', 'AdminG', 'admin-g@example.com', 'organization_administrator')
) as p(id, tenant, fname, email, role);

-- Org structure (service role): two regions, three sites, one foreign-tenant site.
insert into public.regions (id, tenant_id, name) values
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f0001', 'Region North'),
  ('00000000-0000-0000-0000-0000000f1002', '00000000-0000-0000-0000-0000000f0001', 'Region South'),
  ('00000000-0000-0000-0000-0000000f1901', '00000000-0000-0000-0000-0000000f0002', 'Region G');
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f0001', 'Client F'),
  ('00000000-0000-0000-0000-0000000f2901', '00000000-0000-0000-0000-0000000f0002', 'Client G');
insert into public.sites (id, tenant_id, client_id, region_id, name) values
  ('00000000-0000-0000-0000-0000000f3001', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f1001', 'Site A (north)'),
  ('00000000-0000-0000-0000-0000000f3002', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f1001', 'Site B (north)'),
  ('00000000-0000-0000-0000-0000000f3003', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f1002', 'Site C (south)'),
  ('00000000-0000-0000-0000-0000000f3901', '00000000-0000-0000-0000-0000000f0002', '00000000-0000-0000-0000-0000000f2901', '00000000-0000-0000-0000-0000000f1901', 'Site G');

-- The employee profile is also the person an approver could be.
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-0000000f4001', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0101', 'F001', 'AdminOne', 'Test', current_date),
  ('00000000-0000-0000-0000-0000000f4002', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0106', 'F002', 'Emp', 'Test', current_date);

-- Incidents at each site, reported by AdminOne (service-role insert).
insert into public.incidents (id, tenant_id, site_id, category, severity, status, occurred_at, reported_by, description) values
  ('00000000-0000-0000-0000-0000000f5001', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f3001', 'workplace_safety', 'low', 'reported', now(), '00000000-0000-0000-0000-0000000f0101', 'Incident at A'),
  ('00000000-0000-0000-0000-0000000f5002', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f3002', 'workplace_safety', 'low', 'reported', now(), '00000000-0000-0000-0000-0000000f0101', 'Incident at B'),
  ('00000000-0000-0000-0000-0000000f5003', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f3003', 'workplace_safety', 'low', 'reported', now(), '00000000-0000-0000-0000-0000000f0101', 'Incident at C');

-- ---------------------------------------------------------------------------
-- Audit log is append-only.
-- ---------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  perform public.write_audit_log('00000000-0000-0000-0000-0000000f0001', null, 'test_event', 'sites', '00000000-0000-0000-0000-0000000f3001');
  select id into v_id from public.audit_log where action = 'test_event' limit 1;

  begin
    update public.audit_log set action = 'tampered' where id = v_id;
    raise exception 'SECURITY_FAILURE: audit_log UPDATE succeeded for the table owner';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'audit_log_immutable%' then raise exception 'FAIL: expected audit_log_immutable, got %', sqlerrm; end if;
  end;

  begin
    delete from public.audit_log where id = v_id;
    raise exception 'SECURITY_FAILURE: audit_log DELETE succeeded for the table owner';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'audit_log_immutable%' then raise exception 'FAIL: expected audit_log_immutable, got %', sqlerrm; end if;
  end;

  begin
    truncate public.audit_log;
    raise exception 'SECURITY_FAILURE: audit_log TRUNCATE succeeded for the table owner';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'audit_log_immutable%' then raise exception 'FAIL: expected audit_log_immutable, got %', sqlerrm; end if;
  end;

  begin
    perform public.purge_audit_log(interval '1 day');
    raise exception 'SECURITY_FAILURE: audit retention below 365 days was accepted';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'invalid_configuration%' then raise exception 'FAIL: expected invalid_configuration, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: audit_log rejects UPDATE/DELETE/TRUNCATE even for the owner; retention floor enforced';
end $$;

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0101","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    update public.audit_log set action = 'tampered';
    raise exception 'SECURITY_FAILURE: organization_administrator updated audit_log';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;
  begin
    insert into public.audit_log (tenant_id, action, entity_table, entity_id)
    values ('00000000-0000-0000-0000-0000000f0001', 'forged', 'sites', gen_random_uuid());
    raise exception 'SECURITY_FAILURE: organization_administrator inserted into audit_log';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;
  raise notice 'PASS: an organisation administrator can neither forge nor edit audit history';
end $$;

-- ---------------------------------------------------------------------------
-- Role assignment: SoD, security classification, request correlation.
-- ---------------------------------------------------------------------------
do $$
declare v_row record;
begin
  begin
    perform public.admin_update_user_role('00000000-0000-0000-0000-0000000f0101', 'operations_manager');
    raise exception 'SECURITY_FAILURE: user changed their own role';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'separation_of_duties%' then raise exception 'FAIL: expected separation_of_duties, got %', sqlerrm; end if;
  end;

  perform set_config('request.headers', '{"x-request-id":"req-abc-123"}', true);
  perform public.admin_update_user_role('00000000-0000-0000-0000-0000000f0106', 'supervisor');

  select category, outcome, request_id, actor_profile_id into v_row
  from public.audit_log where action = 'role_changed' and entity_id = '00000000-0000-0000-0000-0000000f0106';
  if v_row.category <> 'security' then raise exception 'FAIL: role change not classified as security (%)', v_row.category; end if;
  if v_row.request_id <> 'req-abc-123' then raise exception 'FAIL: request id not captured (%)', v_row.request_id; end if;
  if v_row.actor_profile_id <> '00000000-0000-0000-0000-0000000f0101' then raise exception 'FAIL: actor not recorded'; end if;
  raise notice 'PASS: self role change blocked; role change audited as security with request id and actor';
end $$;

-- ---------------------------------------------------------------------------
-- Separation of duties: leave and incident closure.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;
insert into public.leave_requests (id, tenant_id, employee_id, leave_type_id, start_date, end_date)
select '00000000-0000-0000-0000-0000000f6001', '00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f4001', lt.id, current_date + 60, current_date + 61
from public.leave_types lt where lt.tenant_id = '00000000-0000-0000-0000-0000000f0001' limit 1;

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0101","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.approve_leave_request('00000000-0000-0000-0000-0000000f6001', 'self');
    raise exception 'SECURITY_FAILURE: an employee approved their own leave as an administrator';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'separation_of_duties%' then raise exception 'FAIL: expected separation_of_duties, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: an administrator cannot approve their own leave request';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_status public.leave_status;
begin
  select status into v_status from public.approve_leave_request('00000000-0000-0000-0000-0000000f6001', 'ok');
  if v_status <> 'approved' then raise exception 'FAIL: independent approver could not approve (%)', v_status; end if;
  raise notice 'PASS: an independent administrator can approve the same leave request';
end $$;

-- Incident closure by the reporter is blocked; by another person succeeds.
reset role;
reset request.jwt.claims;
do $$
begin
  perform set_config('app.allow_incident_setup', 'on', true);
  update public.incidents set status = 'acknowledged' where id = '00000000-0000-0000-0000-0000000f5001';
  update public.incidents set status = 'investigating' where id = '00000000-0000-0000-0000-0000000f5001';
  update public.incidents set status = 'corrective_action' where id = '00000000-0000-0000-0000-0000000f5001';
  update public.incidents set status = 'pending_closure' where id = '00000000-0000-0000-0000-0000000f5001';
end $$;

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0101","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.transition_incident_status('00000000-0000-0000-0000-0000000f5001', 'closed', 'closing my own report');
    raise exception 'SECURITY_FAILURE: the reporter closed their own incident';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'separation_of_duties%' then raise exception 'FAIL: expected separation_of_duties, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: the reporter cannot close their own incident';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_status public.incident_status;
begin
  select status into v_status from public.transition_incident_status('00000000-0000-0000-0000-0000000f5001', 'closed', 'verified fixed');
  if v_status <> 'closed' then raise exception 'FAIL: independent closer failed (%)', v_status; end if;
  raise notice 'PASS: an independent person can close the incident';
end $$;

-- ---------------------------------------------------------------------------
-- Scope-aware authorization.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  -- Direct writes to user_scopes are not possible.
  begin
    insert into public.user_scopes (tenant_id, profile_id, scope_type, scope_id)
    values ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0105', 'site', '00000000-0000-0000-0000-0000000f3001');
    raise exception 'SECURITY_FAILURE: direct INSERT into user_scopes succeeded';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;

  -- Cross-tenant scope target rejected.
  begin
    perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0105', 'site', '00000000-0000-0000-0000-0000000f3901');
    raise exception 'SECURITY_FAILURE: granted a scope on another tenant''s site';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'cross_tenant_reference%' then raise exception 'FAIL: expected cross_tenant_reference, got %', sqlerrm; end if;
  end;

  -- Nobody grants themselves a scope.
  begin
    perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0102', 'site', '00000000-0000-0000-0000-0000000f3001');
    raise exception 'SECURITY_FAILURE: user granted themselves a scope';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'separation_of_duties%' then raise exception 'FAIL: expected separation_of_duties, got %', sqlerrm; end if;
  end;

  perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0105', 'site', '00000000-0000-0000-0000-0000000f3001');
  perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0104', 'region', '00000000-0000-0000-0000-0000000f1001');

  select count(*) into v_count from public.audit_log where action = 'scope_granted' and category = 'security';
  if v_count <> 2 then raise exception 'FAIL: expected 2 security-classified scope_granted audit rows, got %', v_count; end if;
  raise notice 'PASS: scope grants are validated, audited as security, and cannot be self-assigned';
end $$;

-- Site manager scoped to site A: sees only A.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0105","app_metadata":{"role":"site_manager"}}';

do $$
declare v_ids uuid[];
begin
  select array_agg(id order by id) into v_ids from public.incidents where tenant_id = '00000000-0000-0000-0000-0000000f0001';
  if v_ids is distinct from array['00000000-0000-0000-0000-0000000f5001'::uuid] then
    raise exception 'FAIL: site manager scoped to site A saw % incident(s): %', coalesce(array_length(v_ids, 1), 0), v_ids;
  end if;
  begin
    perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0105', 'site', '00000000-0000-0000-0000-0000000f3002');
    raise exception 'SECURITY_FAILURE: site manager escalated their own scope';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'insufficient_privilege%' then raise exception 'FAIL: expected insufficient_privilege, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: site manager sees only their assigned site and cannot widen it';
end $$;

-- Regional manager scoped to region North: sees A and B, not C.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0104","app_metadata":{"role":"regional_manager"}}';

do $$
declare v_ids uuid[];
begin
  select array_agg(id order by id) into v_ids from public.incidents where tenant_id = '00000000-0000-0000-0000-0000000f0001';
  if v_ids is distinct from array['00000000-0000-0000-0000-0000000f5001'::uuid, '00000000-0000-0000-0000-0000000f5002'::uuid] then
    raise exception 'FAIL: regional manager (North) saw %', v_ids;
  end if;
  raise notice 'PASS: regional manager sees every site in their region and none outside it';
end $$;

-- Operations manager (tenant-wide) sees all three; foreign tenant sees none.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0103","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents;
  if v_count <> 3 then raise exception 'FAIL: operations manager should see all 3 incidents, saw %', v_count; end if;
  raise notice 'PASS: tenant-wide role is unaffected by scope restrictions';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0201","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: another tenant''s administrator saw % incident(s)', v_count; end if;
  select count(*) into v_count from public.user_scopes;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: another tenant''s administrator saw % scope row(s)', v_count; end if;
  raise notice 'PASS: scope and incident data do not cross tenants';
end $$;

-- Revoking a scope removes access immediately; a scoped role with none fails closed.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0102","app_metadata":{"role":"organization_administrator"}}';
select public.revoke_user_scope(id) from public.user_scopes where profile_id = '00000000-0000-0000-0000-0000000f0105';

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0105","app_metadata":{"role":"site_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.incidents;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: scoped role with no assignments saw % incident(s)', v_count; end if;
  raise notice 'PASS: revoking a scope removes access; scoped roles fail closed';
end $$;

rollback;
