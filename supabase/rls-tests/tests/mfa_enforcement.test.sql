-- Server-side MFA enforcement: privileged roles, and anyone with a verified
-- factor, are refused at aal1 by the database itself.

begin;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f0701', 'Org M', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(), jsonb_build_object('role', u.role), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0711', 'admin-m@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0712', 'ops-m@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0713', 'hr-m@example.com', 'hr_user'),
  ('00000000-0000-0000-0000-0000000f0714', 'platform-m@example.com', 'platform_administrator'),
  ('00000000-0000-0000-0000-0000000f0715', 'emp-m@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0716', 'emp-factor-m@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0717', 'emp-unverified-m@example.com', 'employee'),
  ('00000000-0000-0000-0000-0000000f0718', 'inactive-admin-m@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0719', 'site-m@example.com', 'site_manager')
) as u(id, email, role);

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
select p.id::uuid, case when p.role = 'platform_administrator' then null else '00000000-0000-0000-0000-0000000f0701'::uuid end,
       p.f, 'M', p.email, p.role::public.user_role, p.status::public.profile_status
from (values
  ('00000000-0000-0000-0000-0000000f0711', 'Admin', 'admin-m@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000f0712', 'Ops', 'ops-m@example.com', 'operations_manager', 'active'),
  ('00000000-0000-0000-0000-0000000f0713', 'Hr', 'hr-m@example.com', 'hr_user', 'active'),
  ('00000000-0000-0000-0000-0000000f0714', 'Platform', 'platform-m@example.com', 'platform_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000f0715', 'Emp', 'emp-m@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0716', 'EmpFactor', 'emp-factor-m@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0717', 'EmpUnverified', 'emp-unverified-m@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0718', 'InactiveAdmin', 'inactive-admin-m@example.com', 'organization_administrator', 'inactive'),
  ('00000000-0000-0000-0000-0000000f0719', 'Site', 'site-m@example.com', 'site_manager', 'active')
) as p(id, f, email, role, status);

insert into auth.mfa_factors (user_id, status) values
  ('00000000-0000-0000-0000-0000000f0716', 'verified'),
  ('00000000-0000-0000-0000-0000000f0717', 'unverified');

insert into public.regions (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0721', '00000000-0000-0000-0000-0000000f0701', 'Region M');
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0722', '00000000-0000-0000-0000-0000000f0701', 'Client M');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-0000000f0723', '00000000-0000-0000-0000-0000000f0701', '00000000-0000-0000-0000-0000000f0722', 'Site M');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-0000000f0731', '00000000-0000-0000-0000-0000000f0701', '00000000-0000-0000-0000-0000000f0715', 'M001', 'Emp', 'M', current_date);

-- ---------------------------------------------------------------------------
-- 1. Privileged role at aal1 (and with no aal claim at all): denied everywhere.
-- ---------------------------------------------------------------------------
do $$
declare v_role text; v_aal text; v_n int; v_ok boolean;
begin
  foreach v_role in array array['organization_administrator', 'operations_manager', 'hr_user'] loop
    foreach v_aal in array array['aal1', 'none'] loop
      perform test_util.as_user(
        case v_role when 'organization_administrator' then '00000000-0000-0000-0000-0000000f0711'
                    when 'operations_manager' then '00000000-0000-0000-0000-0000000f0712'
                    else '00000000-0000-0000-0000-0000000f0713' end, v_role, v_aal);
      select count(*) into v_n from public.employees;
      if v_n <> 0 then raise exception 'SECURITY_FAILURE: % at % read % employees', v_role, v_aal, v_n; end if;
      select count(*) into v_n from public.sites;
      if v_n <> 0 then raise exception 'SECURITY_FAILURE: % at % read sites', v_role, v_aal; end if;
      if public.current_tenant_id() is not null then raise exception 'SECURITY_FAILURE: % at % resolved a tenant', v_role, v_aal; end if;
      -- Helpers must return FALSE (never NULL): an RPC's `if not helper() then raise` does not fire on NULL.
      if public.can_manage_operations('00000000-0000-0000-0000-0000000f0701') is distinct from false
         or public.can_manage_employees('00000000-0000-0000-0000-0000000f0701') is distinct from false
         or public.can_manage_profiles('00000000-0000-0000-0000-0000000f0701') is distinct from false
         or public.can_manage_org_structure('00000000-0000-0000-0000-0000000f0701') is distinct from false
         or public.can_approve_leave('00000000-0000-0000-0000-0000000f0701') is distinct from false then
        raise exception 'SECURITY_FAILURE: % at % passed (or returned NULL from) a permission helper', v_role, v_aal;
      end if;
      -- direct writes
      begin
        insert into public.regions (tenant_id, name) values ('00000000-0000-0000-0000-0000000f0701', 'Sneaky');
        raise exception 'SECURITY_FAILURE: % at % inserted a region', v_role, v_aal;
      exception when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      end;
      -- RPCs
      begin
        perform public.create_task('00000000-0000-0000-0000-0000000f0723', 'Sneaky task');
        raise exception 'SECURITY_FAILURE: % at % created a task through the RPC', v_role, v_aal;
      exception when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      end;
      begin
        perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0719', 'site', '00000000-0000-0000-0000-0000000f0723');
        raise exception 'SECURITY_FAILURE: % at % granted a scope', v_role, v_aal;
      exception when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      end;
      begin
        perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0715', 'inactive');
        raise exception 'SECURITY_FAILURE: % at % changed a user status', v_role, v_aal;
      exception when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      end;
      -- own profile stays readable so the app can route them to MFA enrolment
      select count(*) into v_n from public.profiles where id = auth.uid();
      if v_n <> 1 then raise exception 'FAIL: % at % cannot read their own profile (cannot reach MFA enrolment)', v_role, v_aal; end if;
    end loop;
  end loop;
  raise notice 'PASS: privileged roles without MFA are refused for reads, writes and RPCs (aal1 and missing claim)';
end $$;

-- ---------------------------------------------------------------------------
-- 2. The same users at aal2 are allowed.
-- ---------------------------------------------------------------------------
reset role;
do $$
declare v_n int; v_task public.tasks;
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0711', 'organization_administrator', 'aal2');
  select count(*) into v_n from public.sites;
  if v_n <> 1 then raise exception 'FAIL: org admin at aal2 should see the site, saw %', v_n; end if;
  if not public.can_manage_org_structure('00000000-0000-0000-0000-0000000f0701') then raise exception 'FAIL: org admin at aal2 lost permissions'; end if;
  v_task := public.create_task('00000000-0000-0000-0000-0000000f0723', 'Legit task');
  perform public.grant_user_scope('00000000-0000-0000-0000-0000000f0719', 'site', '00000000-0000-0000-0000-0000000f0723');
  perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0715', 'inactive');
  perform public.admin_set_user_status('00000000-0000-0000-0000-0000000f0715', 'active');
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0713', 'hr_user', 'aal2');
  select count(*) into v_n from public.employees;
  if v_n <> 1 then raise exception 'FAIL: hr at aal2 should see employees'; end if;
  raise notice 'PASS: privileged roles with MFA complete can do their jobs';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Platform administrator.
-- ---------------------------------------------------------------------------
reset role;
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0714', 'platform_administrator', 'aal1');
  if public.is_platform_admin() then raise exception 'SECURITY_FAILURE: platform administrator at aal1 is still a platform admin'; end if;
  if (select count(*) from public.organizations) <> 0 then raise exception 'SECURITY_FAILURE: platform administrator at aal1 can list organizations'; end if;
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0714', 'platform_administrator', 'aal2');
  if not public.is_platform_admin() then raise exception 'FAIL: platform administrator at aal2 lost platform rights'; end if;
  if (select count(*) from public.organizations) < 1 then raise exception 'FAIL: platform administrator at aal2 cannot list organizations'; end if;
  raise notice 'PASS: platform administrator needs MFA';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Non-privileged users: only those who enrolled a (verified) factor are held to aal2.
-- ---------------------------------------------------------------------------
reset role;
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0715', 'employee', 'aal1');
  if public.current_tenant_id() is null then raise exception 'FAIL: an employee with no factor must not need MFA'; end if;
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0717', 'employee', 'aal1');
  if public.current_tenant_id() is null then raise exception 'FAIL: an UNVERIFIED factor must not lock the user out'; end if;
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0716', 'employee', 'aal1');
  if public.current_tenant_id() is not null then raise exception 'SECURITY_FAILURE: a user with a verified factor was served at aal1'; end if;
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0716', 'employee', 'aal2');
  if public.current_tenant_id() is null then raise exception 'FAIL: a user with a verified factor must be served at aal2'; end if;
  -- scoped operational roles without a factor are not forced (they are not in mfa_roles()).
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0719', 'site_manager', 'aal1');
  if public.current_tenant_id() is null then raise exception 'FAIL: site manager without a factor must not need MFA'; end if;
  raise notice 'PASS: enrolled users are held to aal2, others are not';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Deactivation still wins over MFA.
-- ---------------------------------------------------------------------------
reset role;
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0718', 'organization_administrator', 'aal2');
  if public.current_tenant_id() is not null or (select count(*) from public.sites) <> 0 then
    raise exception 'SECURITY_FAILURE: a deactivated administrator with aal2 still reaches tenant data';
  end if;
  raise notice 'PASS: deactivated accounts stay blocked even at aal2';
end $$;

-- ---------------------------------------------------------------------------
-- 6. The switch: not reachable by application users; break-glass works and restores.
-- ---------------------------------------------------------------------------
reset role;
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0711', 'organization_administrator', 'aal2');
  begin
    perform 1 from public.security_settings;
    raise exception 'SECURITY_FAILURE: authenticated can read security_settings';
  exception when others then if sqlerrm like 'SECURITY_FAILURE%' then raise; end if; end;
  begin
    update public.security_settings set bool_value = false where key = 'mfa_enforced';
    raise exception 'SECURITY_FAILURE: authenticated can change security_settings';
  exception when others then if sqlerrm like 'SECURITY_FAILURE%' then raise; end if; end;
  raise notice 'PASS: application users cannot read or change the MFA switch';
end $$;

reset role;
update public.security_settings set bool_value = false where key = 'mfa_enforced';
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0711', 'organization_administrator', 'aal1');
  if (select count(*) from public.sites) <> 1 then raise exception 'FAIL: break-glass (enforcement off) should let an administrator recover access'; end if;
  raise notice 'PASS: operator break-glass restores access when enforcement is switched off';
end $$;
reset role;
update public.security_settings set bool_value = true where key = 'mfa_enforced';
do $$
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000f0711', 'organization_administrator', 'aal1');
  if (select count(*) from public.sites) <> 0 then raise exception 'SECURITY_FAILURE: enforcement did not resume'; end if;
  raise notice 'PASS: enforcement resumes when switched back on';
end $$;

rollback;
