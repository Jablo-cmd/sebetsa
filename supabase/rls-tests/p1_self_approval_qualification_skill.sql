-- Sebetsa — regression coverage for the P1 security remediation
-- (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining Risks" #1 — the audit's
-- HIGH self-approval finding for verify_employee_qualification/
-- verify_employee_skill, omitted from the prior remediation pass; fixed
-- in 20260920090000_p1_self_approval_qualification_skill.sql).
--
-- Confirmed by running this file against the pre-fix function bodies:
-- every SECURITY_FAILURE-labelled assertion below reproducibly failed
-- (an organization_administrator who is also an employee could verify
-- their own skill/qualification) before the fix, and passes after it.
--
--   supabase start
--   cat supabase/rls-tests/p1_self_approval_qualification_skill.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

-- ---------------------------------------------------------------------------
-- Tenant A: a manager who is also an employee (self-verification target),
-- plus a second ordinary employee (the legitimate-verification target).

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000fb01', 'Tenant A (skill/qualification self-approval)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fb02', 'authenticated', 'authenticated', 'admin-fb@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000fb02', '00000000-0000-0000-0000-00000000fb01', 'Admin', 'Self', 'admin-fb@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fb02","app_metadata":{"role":"organization_administrator"}}';

-- The admin is also an employee (the self-verification scenario) ...
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000fb03', '00000000-0000-0000-0000-00000000fb01', '00000000-0000-0000-0000-00000000fb02', 'FB001', 'Admin', 'Self', current_date - 100);

-- ... and a different, ordinary employee (the legitimate-verification target, no auth.users row needed — they never call an RPC themselves).
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000fb04', '00000000-0000-0000-0000-00000000fb01', null, 'FB002', 'Other', 'Employee', current_date - 100);

insert into public.skills (id, tenant_id, name, category) values
  ('00000000-0000-0000-0000-00000000fb05', '00000000-0000-0000-0000-00000000fb01', 'First Aid', 'safety');

do $$
begin
  perform public.set_employee_skill('00000000-0000-0000-0000-00000000fb03', '00000000-0000-0000-0000-00000000fb05', 'intermediate');
  perform public.set_employee_skill('00000000-0000-0000-0000-00000000fb04', '00000000-0000-0000-0000-00000000fb05', 'intermediate');
end $$;

do $$
begin
  perform public.upsert_employee_qualification(null, '00000000-0000-0000-0000-00000000fb03', 'certification', 'First Aid Cert');
  perform public.upsert_employee_qualification(null, '00000000-0000-0000-0000-00000000fb04', 'certification', 'First Aid Cert');
end $$;

-- ---------------------------------------------------------------------------
-- SKILL: self-verification is denied.
do $$
declare v_skill_id uuid;
begin
  select id into v_skill_id from public.employee_skills where employee_id = '00000000-0000-0000-0000-00000000fb03';
  begin
    perform public.verify_employee_skill(v_skill_id);
    raise exception 'SECURITY_FAILURE: organization_administrator verified their own skill';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: organization_administrator cannot verify their own skill (%)', sqlerrm;
  end;
end $$;

-- SKILL: verifying a different employee's skill still succeeds (proves the
-- guard is specifically self-vs-subject, not a blanket new denial).
do $$
declare v_skill_id uuid; v_result public.employee_skills;
begin
  select id into v_skill_id from public.employee_skills where employee_id = '00000000-0000-0000-0000-00000000fb04';
  select * into v_result from public.verify_employee_skill(v_skill_id);
  if v_result.verified_by is null then raise exception 'FAIL: verifying a different employee''s skill did not record verified_by'; end if;
  raise notice 'PASS: organization_administrator can verify a different employee''s skill';
end $$;

-- ---------------------------------------------------------------------------
-- QUALIFICATION: self-verification is denied.
do $$
declare v_qual_id uuid;
begin
  select id into v_qual_id from public.employee_qualifications where employee_id = '00000000-0000-0000-0000-00000000fb03';
  begin
    perform public.verify_employee_qualification(v_qual_id, true);
    raise exception 'SECURITY_FAILURE: organization_administrator verified their own qualification';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: organization_administrator cannot verify their own qualification (%)', sqlerrm;
  end;
end $$;

-- QUALIFICATION: manipulated ID — passing another employee's qualification
-- row id changes nothing about the self-check outcome (the guard is
-- derived from the row's own employee_id via a join, never from a
-- client-supplied employee id parameter, so there is no id to manipulate
-- into a false "not self" result).
do $$
declare v_qual_id uuid; v_result public.employee_qualifications;
begin
  select id into v_qual_id from public.employee_qualifications where employee_id = '00000000-0000-0000-0000-00000000fb04';
  select * into v_result from public.verify_employee_qualification(v_qual_id, true);
  if v_result.status <> 'verified' then raise exception 'FAIL: verifying a different employee''s qualification did not succeed'; end if;
  raise notice 'PASS: organization_administrator can verify a different employee''s qualification';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Tenant B: cross-tenant verification attempt is denied (can_manage_employees'
-- own tenant comparison, unchanged by this fix, still applies first).

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000fc01', 'Tenant B (cross-tenant verification attempt)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fc02', 'authenticated', 'authenticated', 'admin-fc@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000fc02', '00000000-0000-0000-0000-00000000fc01', 'Admin', 'B', 'admin-fc@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fc02","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_skill_id uuid;
begin
  -- Tenant B's admin attempts to verify Tenant A's (fb04) skill record.
  select id into v_skill_id from public.employee_skills where employee_id = '00000000-0000-0000-0000-00000000fb04';
  begin
    perform public.verify_employee_skill(v_skill_id);
    raise exception 'SECURITY_FAILURE: Tenant B admin verified a Tenant A employee''s skill';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant skill verification is denied (%)', sqlerrm;
  end;
end $$;

do $$
declare v_qual_id uuid;
begin
  select id into v_qual_id from public.employee_qualifications where employee_id = '00000000-0000-0000-0000-00000000fb04';
  begin
    perform public.verify_employee_qualification(v_qual_id, true);
    raise exception 'SECURITY_FAILURE: Tenant B admin verified a Tenant A employee''s qualification';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant qualification verification is denied (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
