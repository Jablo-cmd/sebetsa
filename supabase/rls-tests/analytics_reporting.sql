-- Sebetsa Phase R — Analytics, Reporting & Management Intelligence: checks.
--
-- The critical property under test: get_operational_metrics() is SECURITY
-- INVOKER, so its aggregates must be scoped by the CALLER's own RLS, not
-- see the whole tenant regardless of role. This is the one place in
-- Sebetsa where a mistaken `security definer` would be a real,
-- cross-tenant/cross-role data-leak bug, not just a permission gap — so
-- this suite proves the invoker design actually holds, not merely that
-- the function runs.
--
--   supabase start
--   cat supabase/rls-tests/analytics_reporting.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000591', 'Org R1', 'active'),
  ('00000000-0000-0000-0000-000000000592', 'Org R2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005901', 'authenticated', 'authenticated', 'admin-r1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005902', 'authenticated', 'authenticated', 'employee-r1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-000000000591', 'Admin', 'R1', 'admin-r1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000005902', '00000000-0000-0000-0000-000000000591', 'Emp', 'R1', 'employee-r1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005901","app_metadata":{"role":"organization_administrator"}}';

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_status) values
  ('00000000-0000-0000-0000-000000006591', '00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000005902', 'EMP-R1', 'Emp', 'R1', 'active'),
  ('00000000-0000-0000-0000-000000006592', '00000000-0000-0000-0000-000000000591', null, 'EMP-R2', 'Other', 'Worker', 'active');

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003591', '00000000-0000-0000-0000-000000000591', 'Client R1');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004591', '00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000003591', 'Site R1');

insert into public.tasks (tenant_id, site_id, assignee_id, title, status, due_at) values
  ('00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000004591', '00000000-0000-0000-0000-000000006591', 'Task A', 'completed', '2026-09-10T09:00:00Z'),
  ('00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000004591', '00000000-0000-0000-0000-000000006592', 'Task B', 'open', '2026-09-11T09:00:00Z'),
  -- Overdue and assigned ONLY to the other employee (6592) — the proof
  -- point below is that employee-5902's own tasks_select_own_or_broad
  -- scoping (own-assignee-only, no broad tier) hides this row, so their
  -- overdue_task_count must be 0 even though the tenant-wide count is 1.
  ('00000000-0000-0000-0000-000000000591', '00000000-0000-0000-0000-000000004591', '00000000-0000-0000-0000-000000006592', 'Task C (overdue)', 'open', '2020-01-01T09:00:00Z');

-- ---------------------------------------------------------------------------
-- The management-tier caller sees the full, real tenant-wide aggregate.

do $$
declare v_employees bigint; v_overdue bigint;
begin
  select active_employee_count, overdue_task_count
    into v_employees, v_overdue
  from public.get_operational_metrics('00000000-0000-0000-0000-000000000591', '2026-09-01', '2026-09-30');

  if v_employees <> 2 then raise exception 'FAIL: expected 2 active employees, got %', v_employees; end if;
  if v_overdue <> 2 then raise exception 'FAIL: expected 2 overdue tasks tenant-wide, got %', v_overdue; end if;
  raise notice 'PASS: organization_administrator sees the real tenant-wide aggregate (2 employees, 2 overdue tasks)';
end $$;

-- ---------------------------------------------------------------------------
-- The plain-employee caller, via the SAME SECURITY-INVOKER function, sees
-- only what their own RLS already permits — proving no cross-role leak.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005902","app_metadata":{"role":"employee"}}';

do $$
declare v_overdue bigint;
begin
  select overdue_task_count into v_overdue
  from public.get_operational_metrics('00000000-0000-0000-0000-000000000591', '2026-09-01', '2026-09-30');

  if v_overdue <> 0 then
    raise exception 'SECURITY_FAILURE: plain employee''s get_operational_metrics call saw % overdue tasks (the one overdue task belongs to a different employee and tasks_select_own_or_broad should hide it)', v_overdue;
  end if;
  raise notice 'PASS: plain-employee call sees 0 overdue tasks — tasks_select_own_or_broad''s existing own-assignee scoping applies through the SECURITY INVOKER analytics RPC, proving no cross-role leak';
end $$;

-- ---------------------------------------------------------------------------
-- Cross-tenant isolation: an admin of a different tenant sees nothing for
-- this tenant, even by passing its id explicitly.

reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005903', 'authenticated', 'authenticated', 'admin-r2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000005903', '00000000-0000-0000-0000-000000000592', 'Admin', 'R2', 'admin-r2@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000005903","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_employees bigint;
begin
  select active_employee_count into v_employees
  from public.get_operational_metrics('00000000-0000-0000-0000-000000000591', '2026-09-01', '2026-09-30');

  if v_employees <> 0 then
    raise exception 'SECURITY_FAILURE: a foreign-tenant admin''s get_operational_metrics call for tenant R1 saw % employees', v_employees;
  end if;
  raise notice 'PASS: cross-tenant call to get_operational_metrics returns 0 — tenant isolation holds even for an explicit foreign tenant_id argument';
end $$;

reset role;
reset request.jwt.claims;

rollback;
