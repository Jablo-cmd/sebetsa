-- Sebetsa Phase S — Site Survey: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/site_surveys.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000591', 'Org S1', 'active'),
  ('00000000-0000-0000-0000-000000000592', 'Org S2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005901', 'authenticated', 'authenticated', 'admin-s1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005902', 'authenticated', 'authenticated', 'employee-s1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-000000000591', 'Admin', 'S1', 'admin-s1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000005902', '00000000-0000-0000-0000-000000000591', 'Emp', 'S1', 'employee-s1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000005391', '00000000-0000-0000-0000-000000000591', 'Prospect S1');

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000005392', '00000000-0000-0000-0000-000000000592', 'Prospect S2');

-- ---------------------------------------------------------------------------
-- Creation + tenant isolation + write tier.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005901","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.site_surveys (tenant_id, client_id, prospective_site_name)
    values ('00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000005392', 'Cross-tenant prospect HQ');
    raise exception 'SECURITY_FAILURE: cross-tenant site_surveys.client_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant site_surveys.client_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.site_surveys (id, tenant_id, client_id, prospective_site_name, address, building_type, bathroom_count, office_count)
values ('00000000-0000-0000-0000-000000006391', '00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000005391', 'ABC Corporate Park', '1 Main Rd', 'Office park', 4, 20);

update public.site_surveys set status = 'completed' where id = '00000000-0000-0000-0000-000000006391';

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005902","app_metadata":{"role":"employee"}}';

do $$
declare v_rows int;
begin
  update public.site_surveys set prospective_site_name = 'Hijacked' where id = '00000000-0000-0000-0000-000000006391';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: plain employee updated a site survey (% rows)', v_rows; end if;
  raise notice 'PASS: plain-employee site_surveys write blocked by RLS (0 rows affected)';
end $$;

-- ---------------------------------------------------------------------------
-- convert_site_survey_to_site: creates a real site, exactly once.

do $$
begin
  begin
    perform public.convert_site_survey_to_site('00000000-0000-0000-0000-000000006391');
    raise exception 'SECURITY_FAILURE: plain employee converted a site survey to a site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee convert_site_survey_to_site blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_site public.sites; v_survey_status public.site_survey_status;
begin
  select * into v_site from public.convert_site_survey_to_site('00000000-0000-0000-0000-000000006391');
  if v_site.name <> 'ABC Corporate Park' then raise exception 'FAIL: expected new site name from survey, got %', v_site.name; end if;
  if v_site.client_id <> '00000000-0000-0000-0000-000000005391' then raise exception 'FAIL: new site not linked to the survey''s client'; end if;
  if v_site.status <> 'onboarding' then raise exception 'FAIL: expected new site status onboarding, got %', v_site.status; end if;

  select status into v_survey_status from public.site_surveys where id = '00000000-0000-0000-0000-000000006391';
  if v_survey_status <> 'converted' then raise exception 'FAIL: expected survey status converted, got %', v_survey_status; end if;
  raise notice 'PASS: convert_site_survey_to_site creates a real site from the survey''s own data and marks the survey converted';
end $$;

do $$
begin
  begin
    perform public.convert_site_survey_to_site('00000000-0000-0000-0000-000000006391');
    raise exception 'SECURITY_FAILURE: an already-converted site survey was converted a second time';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-converted site survey cannot be converted again (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Append-only audit check.

do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'site_surveys' and action = 'site_survey_converted_to_site';
  if v_count < 1 then raise exception 'FAIL: site survey conversion was not audit-logged'; end if;
  raise notice 'PASS: site survey conversion is audit-logged';
end $$;

rollback;
