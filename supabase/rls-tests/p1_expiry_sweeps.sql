-- Sebetsa — regression coverage for the P1 expiry-sweep scheduling
-- (docs/PRODUCTION_READINESS_AUDIT.md, fixed in
-- 20260919090700_p1_expiry_sweep_scheduling.sql).
--
-- The per-tenant sync_expired_compliance_records()/sync_expired_qualifications()
-- RPCs are exercised elsewhere (compliance_incidents.sql,
-- workforce_performance_training_skills.sql) — this file instead proves
-- the NEW system-wide sweep functions the scheduled job calls: that they
-- correctly expire past-due records across tenants with no caller
-- context, and that an ordinary authenticated user (even a privileged one)
-- can never invoke the "sweep everything" variant directly.
--
--   supabase start
--   cat supabase/rls-tests/p1_expiry_sweeps.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000e91', 'Org I1', 'active'),
  ('00000000-0000-0000-0000-000000000e92', 'Org I2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000e93', 'authenticated', 'authenticated', 'admin-i1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000e94', 'authenticated', 'authenticated', 'admin-i2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-000000000e93', '00000000-0000-0000-0000-000000000e91', 'Admin', 'I1', 'admin-i1@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-000000000e94', '00000000-0000-0000-0000-000000000e92', 'Admin', 'I2', 'admin-i2@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000e93","app_metadata":{"role":"organization_administrator"}}';

insert into public.compliance_requirements (id, tenant_id, name, category, applies_to_scope) values
  ('00000000-0000-0000-0000-000000000e95', '00000000-0000-0000-0000-000000000e91', 'Fire Safety', 'safety', 'organization');

do $$
declare v_id uuid;
begin
  select id into v_id from public.upsert_compliance_record(
    null, '00000000-0000-0000-0000-000000000e95', null, null, null,
    null, current_date - 30, current_date - 1, null, 'expired last month'
  );
  perform public.verify_compliance_record(v_id, true);
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000e94","app_metadata":{"role":"organization_administrator"}}';

insert into public.compliance_requirements (id, tenant_id, name, category, applies_to_scope) values
  ('00000000-0000-0000-0000-000000000e96', '00000000-0000-0000-0000-000000000e92', 'Fire Safety I2', 'safety', 'organization');

do $$
declare v_id uuid;
begin
  select id into v_id from public.upsert_compliance_record(
    null, '00000000-0000-0000-0000-000000000e96', null, null, null,
    null, current_date - 30, current_date - 1, null, 'expired last month too'
  );
  perform public.verify_compliance_record(v_id, true);
end $$;

reset role;
reset request.jwt.claims;

-- Ordinary authenticated users (even a privileged one) must never be able
-- to call the system-wide sweep directly — it exists only for the
-- scheduler, which runs with no request-scoped JWT at all.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000e93","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    perform public.sync_all_expired_compliance_records();
    raise exception 'SECURITY_FAILURE: an ordinary authenticated user called the system-wide compliance sweep directly';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: authenticated users cannot call sync_all_expired_compliance_records() directly (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- Before the sweep runs: both tenants' records still show their
-- pre-sweep status (proves the sweep, not something else, causes the
-- change below).
do $$
declare v_status public.compliance_status;
begin
  select status into v_status from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000000e95';
  if v_status <> 'compliant' then raise exception 'test setup error: expected compliant before sweep, got %', v_status; end if;
end $$;

-- The scheduler's own call: no role/claims set at all (this IS the
-- no-caller-context the fix exists for).
do $$
begin
  perform public.sync_all_expired_compliance_records();
end $$;

do $$
declare v_status_1 public.compliance_status; v_status_2 public.compliance_status;
begin
  select status into v_status_1 from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000000e95';
  select status into v_status_2 from public.compliance_records where requirement_id = '00000000-0000-0000-0000-000000000e96';
  if v_status_1 <> 'expired' then raise exception 'FAIL: tenant I1''s expired compliance record was not swept, status=%', v_status_1; end if;
  if v_status_2 <> 'expired' then raise exception 'FAIL: tenant I2''s expired compliance record was not swept, status=%', v_status_2; end if;
  raise notice 'PASS: sync_all_expired_compliance_records() expires past-due records across BOTH tenants with no caller context';
end $$;

rollback;
