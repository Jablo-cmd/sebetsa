-- Sebetsa Domain 15 — Workforce Intelligence + AI.
-- Regression coverage for ai_query_log, shift_recommendations and the
-- deterministic insight/scheduling RPCs
-- (supabase/migrations/20260921090500_workforce_intelligence.sql).
--
--   supabase start
--   cat supabase/rls-tests/domain15_workforce_intelligence.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000f101', 'Tenant A (Domain 15)', 'active'),
  ('00000000-0000-0000-0000-00000000f201', 'Tenant B (Domain 15 cross-tenant)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f102', 'authenticated', 'authenticated', 'admin-f1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f103', 'authenticated', 'authenticated', 'guard-f1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f104', 'authenticated', 'authenticated', 'other-f1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f202', 'authenticated', 'authenticated', 'admin-f2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000f102', '00000000-0000-0000-0000-00000000f101', 'Admin', 'F1', 'admin-f1@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000f103', '00000000-0000-0000-0000-00000000f101', 'Guard', 'One', 'guard-f1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000f104', '00000000-0000-0000-0000-00000000f101', 'Other', 'Guard', 'other-f1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000f202', '00000000-0000-0000-0000-00000000f201', 'Admin', 'F2', 'admin-f2@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f102","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000f105', '00000000-0000-0000-0000-00000000f101', 'Client F1');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000000f106', '00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-00000000f105', 'Site F1', 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date, employment_status) values
  ('00000000-0000-0000-0000-00000000f107', '00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-00000000f103', 'F1001', 'Guard', 'One', current_date - 60, 'active'),
  ('00000000-0000-0000-0000-00000000f108', '00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-00000000f104', 'F1002', 'Other', 'Guard', current_date - 60, 'active');
insert into public.site_assignments (tenant_id, site_id, employee_id) values
  ('00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-00000000f106', '00000000-0000-0000-0000-00000000f107');

-- One staffing requirement of 2 with only 1 assigned — a real, deterministic
-- understaffing case.
insert into public.site_staffing_requirements (tenant_id, site_id, label, required_count) values
  ('00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-00000000f106', 'Day shift guards', 2);

-- A qualification expiring in 10 days — inside the default 30-day window.
do $$
begin
  perform public.upsert_employee_qualification(null, '00000000-0000-0000-0000-00000000f107', 'qualification', 'PSIRA Grade C', 'PSIRA', current_date - 300, current_date + 10);
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Deterministic insight tools: real figures, no hardcoding, RLS-scoped
-- regardless of the client-supplied p_tenant_id argument.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_row record; v_count int := 0;
begin
  for v_row in select * from public.get_understaffed_sites('00000000-0000-0000-0000-00000000f101') loop
    v_count := v_count + 1;
    if v_row.site_id <> '00000000-0000-0000-0000-00000000f106' then raise exception 'FAIL: unexpected site in understaffed-sites result'; end if;
    if v_row.shortfall <> 1 then raise exception 'FAIL: expected shortfall=1 (2 required, 1 assigned), got %', v_row.shortfall; end if;
  end loop;
  if v_count <> 1 then raise exception 'FAIL: expected exactly 1 understaffed site, got %', v_count; end if;
  raise notice 'PASS: get_understaffed_sites() returns a real, live, deterministic figure — not a hardcoded stat';
end $$;

do $$
declare v_row record; v_count int := 0;
begin
  for v_row in select * from public.get_expiring_qualifications('00000000-0000-0000-0000-00000000f101', 30) loop
    v_count := v_count + 1;
    if v_row.employee_id <> '00000000-0000-0000-0000-00000000f107' then raise exception 'FAIL: unexpected employee in expiring-qualifications result'; end if;
  end loop;
  if v_count <> 1 then raise exception 'FAIL: expected exactly 1 expiring qualification, got %', v_count; end if;
  raise notice 'PASS: get_expiring_qualifications() correctly finds a real qualification inside the requested window';
end $$;

reset role;
reset request.jwt.claims;

-- Cross-tenant: passing Tenant A's id from a Tenant B caller returns
-- nothing — RLS on the underlying tables governs, not the parameter.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.get_understaffed_sites('00000000-0000-0000-0000-00000000f101');
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A understaffed-site data via a spoofed p_tenant_id'; end if;

  select count(*) into v_count from public.get_expiring_qualifications('00000000-0000-0000-0000-00000000f101', 30);
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A expiring-qualification data via a spoofed p_tenant_id'; end if;

  raise notice 'PASS: insight tools cannot be used to read another tenant''s data via a spoofed p_tenant_id — RLS on the underlying tables governs, not the parameter';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- AI query log: append-only, actor sees their own, ops-tier sees the whole
-- tenant, cross-tenant denied, no arbitrary SQL ever logged (matched_intent
-- + tool_calls only — structural proof there is no free-text SQL column).

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f103","app_metadata":{"role":"employee"}}';

do $$
declare v_log public.ai_query_log;
begin
  select * into v_log from public.log_ai_query('Which sites are understaffed?', 'get_understaffed_sites', '[{"tool":"get_understaffed_sites","args":{}}]'::jsonb, '1 site is currently understaffed.', 'rule_based');
  if v_log.actor_profile_id <> '00000000-0000-0000-0000-00000000f103' then raise exception 'FAIL: ai_query_log recorded the wrong actor'; end if;
  raise notice 'PASS: an employee can log an AI-assistant query, routed only through a whitelisted tool';
end $$;

reset role;
reset request.jwt.claims;

-- A different employee (same tenant) cannot read someone else's AI query log.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f104","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.ai_query_log where actor_profile_id = '00000000-0000-0000-0000-00000000f103';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a co-worker read another employee''s AI query log'; end if;
  raise notice 'PASS: a co-worker cannot read another employee''s AI query log';
end $$;

reset role;
reset request.jwt.claims;

-- Ops-tier can see the whole tenant's AI query log (troubleshooting/audit).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.ai_query_log where actor_profile_id = '00000000-0000-0000-0000-00000000f103';
  if v_count <> 1 then raise exception 'FAIL: expected the org admin to see the employee''s logged AI query for audit purposes, got %', v_count; end if;
  raise notice 'PASS: operations-tier can audit the tenant''s full AI query log';
end $$;

reset role;
reset request.jwt.claims;

-- Cross-tenant denial.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f202","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.ai_query_log where tenant_id = '00000000-0000-0000-0000-00000000f101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A''s AI query log'; end if;
  raise notice 'PASS: cross-tenant AI query log data is denied';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- AI-assisted scheduling: GENERATE -> REVIEW -> ACCEPT/REJECT -> PUBLISH.
-- Nothing ever writes a real `shifts` row except an explicit human decision.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f103","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.generate_shift_recommendations('00000000-0000-0000-0000-00000000f106', current_date + 1, (current_date + 1)::timestamptz + interval '8 hours', (current_date + 1)::timestamptz + interval '16 hours');
    raise exception 'SECURITY_FAILURE: an ordinary employee generated scheduling recommendations';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an ordinary employee cannot generate scheduling recommendations (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f102","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int; v_rec_id uuid; v_shift_count_before int; v_shift_count_after int; v_result public.shift_recommendations;
begin
  select count(*) into v_count from public.generate_shift_recommendations('00000000-0000-0000-0000-00000000f106', current_date + 1, (current_date + 1)::timestamptz + interval '8 hours', (current_date + 1)::timestamptz + interval '16 hours');
  if v_count <> 1 then raise exception 'FAIL: expected exactly 1 candidate recommendation (only Guard One is assigned to the site), got %', v_count; end if;
  raise notice 'PASS: generate_shift_recommendations() produces a real, scored candidate list — GENERATE step only, nothing published yet';

  select id into v_rec_id from public.shift_recommendations where site_id = '00000000-0000-0000-0000-00000000f106' and status = 'suggested';

  select count(*) into v_shift_count_before from public.shifts where employee_id = '00000000-0000-0000-0000-00000000f107';

  -- REJECT path: never touches `shifts`.
  select * into v_result from public.decide_shift_recommendation(v_rec_id, false);
  if v_result.status <> 'rejected' then raise exception 'FAIL: expected rejected, got %', v_result.status; end if;
  select count(*) into v_shift_count_after from public.shifts where employee_id = '00000000-0000-0000-0000-00000000f107';
  if v_shift_count_after <> v_shift_count_before then raise exception 'SECURITY_FAILURE: rejecting a shift recommendation still created a real shift'; end if;
  raise notice 'PASS: rejecting a recommendation never creates a real shift';

  begin
    perform public.decide_shift_recommendation(v_rec_id, true);
    raise exception 'SECURITY_FAILURE: an already-decided (rejected) recommendation was decided again';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-decided recommendation cannot be decided again (%)', sqlerrm;
  end;

  -- Regenerate and this time ACCEPT: a real, human-approved `shifts` row
  -- appears only now — never automatically.
  perform public.generate_shift_recommendations('00000000-0000-0000-0000-00000000f106', current_date + 1, (current_date + 1)::timestamptz + interval '8 hours', (current_date + 1)::timestamptz + interval '16 hours');
  select id into v_rec_id from public.shift_recommendations where site_id = '00000000-0000-0000-0000-00000000f106' and status = 'suggested';

  select * into v_result from public.decide_shift_recommendation(v_rec_id, true);
  if v_result.status <> 'published' then raise exception 'FAIL: expected published, got %', v_result.status; end if;
  if v_result.published_shift_id is null then raise exception 'FAIL: accepting a recommendation must link the real shift it created'; end if;

  select count(*) into v_shift_count_after from public.shifts where id = v_result.published_shift_id and employee_id = '00000000-0000-0000-0000-00000000f107';
  if v_shift_count_after <> 1 then raise exception 'FAIL: accepting a recommendation must create exactly one real shifts row'; end if;
  raise notice 'PASS: accepting a recommendation is the ONLY path that creates a real shift — an explicit human ACCEPT, never an automatic AI publish';
end $$;

reset role;
reset request.jwt.claims;

-- Cross-tenant: Tenant B admin cannot generate/decide against Tenant A's site/recommendation.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000f202","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.generate_shift_recommendations('00000000-0000-0000-0000-00000000f106', current_date + 2, (current_date + 2)::timestamptz + interval '8 hours', (current_date + 2)::timestamptz + interval '16 hours');
    raise exception 'SECURITY_FAILURE: Tenant B admin generated scheduling recommendations for a Tenant A site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant scheduling-recommendation generation is denied (%)', sqlerrm;
  end;
end $$;

do $$
declare v_rec_id uuid;
begin
  select id into v_rec_id from public.shift_recommendations where tenant_id = '00000000-0000-0000-0000-00000000f101' limit 1;
  begin
    perform public.decide_shift_recommendation(v_rec_id, true);
    raise exception 'SECURITY_FAILURE: Tenant B admin decided a Tenant A shift recommendation';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant shift-recommendation decision is denied (%)', sqlerrm;
  end;
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shift_recommendations where tenant_id = '00000000-0000-0000-0000-00000000f101';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Tenant B admin read Tenant A''s shift recommendations'; end if;
  raise notice 'PASS: cross-tenant shift-recommendation data is denied';
end $$;

reset role;
reset request.jwt.claims;

rollback;
