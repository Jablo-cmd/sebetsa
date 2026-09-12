-- Sebetsa Phase Q — Workforce Performance, Training & Skills: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/workforce_performance_training_skills.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000491', 'Org Q1', 'active'),
  ('00000000-0000-0000-0000-000000000492', 'Org Q2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004901', 'authenticated', 'authenticated', 'hr-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004902', 'authenticated', 'authenticated', 'employee-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004903', 'authenticated', 'authenticated', 'site-mgr-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000004901', '00000000-0000-0000-0000-000000000491', 'HR', 'Q1', 'hr-q1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000004902', '00000000-0000-0000-0000-000000000491', 'Emp', 'Q1', 'employee-q1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000004903', '00000000-0000-0000-0000-000000000491', 'Site', 'MgrQ1', 'site-mgr-q1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"hr_user"}}';

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_status) values
  ('00000000-0000-0000-0000-000000005491', '00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000004902', 'EMP-Q1', 'Emp', 'Q1', 'active');

insert into public.skills (id, tenant_id, name, category)
values ('00000000-0000-0000-0000-000000006491', '00000000-0000-0000-0000-000000000491', 'First Aid', 'safety');

insert into public.training_programs (id, tenant_id, name, category)
values ('00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000000491', 'Fire Safety Induction', 'safety');

-- ---------------------------------------------------------------------------
-- Skills: self-service set, manager-only verify, site_manager (operational,
-- non-HR tier) cannot see or write.

do $$
declare v_id uuid; v_level public.proficiency_level;
begin
  select id, proficiency_level into v_id, v_level from public.set_employee_skill('00000000-0000-0000-0000-000000005491', '00000000-0000-0000-0000-000000006491', 'intermediate');
  if v_level <> 'intermediate' then raise exception 'FAIL: expected intermediate, got %', v_level; end if;
  raise notice 'PASS: hr_user can set an employee skill (%)', v_id;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004902","app_metadata":{"role":"employee"}}';

do $$
declare v_level public.proficiency_level;
begin
  select proficiency_level into v_level from public.set_employee_skill('00000000-0000-0000-0000-000000005491', '00000000-0000-0000-0000-000000006491', 'advanced');
  if v_level <> 'advanced' then raise exception 'FAIL: expected advanced, got %', v_level; end if;
  raise notice 'PASS: employee can self-set their own skill proficiency';
end $$;

do $$
declare v_id uuid;
begin
  select id into v_id from public.employee_skills where employee_id = '00000000-0000-0000-0000-000000005491';
  begin
    perform public.verify_employee_skill(v_id);
    raise exception 'SECURITY_FAILURE: plain employee verified their own skill';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee verify_employee_skill blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004903","app_metadata":{"role":"site_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_skills where tenant_id = '00000000-0000-0000-0000-000000000491';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: site_manager (non-HR operational tier) can see % employee_skills rows', v_count; end if;
  raise notice 'PASS: site_manager (operational, non-HR tier) sees 0 rows — performance/skills privacy holds';
end $$;

-- ---------------------------------------------------------------------------
-- Qualifications: manager creates, verifies; append-only-ish (no direct write).

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"hr_user"}}';

do $$
declare v_id uuid; v_status public.credential_status;
begin
  select id, status into v_id, v_status from public.upsert_employee_qualification(
    null, '00000000-0000-0000-0000-000000005491', 'certification', 'First Aid Certificate', 'Red Cross', '2026-01-01', '2027-01-01', null
  );
  if v_status <> 'pending_verification' then raise exception 'FAIL: expected pending_verification, got %', v_status; end if;

  select status into v_status from public.verify_employee_qualification(v_id, true);
  if v_status <> 'verified' then raise exception 'FAIL: expected verified, got %', v_status; end if;
  raise notice 'PASS: qualification created pending, then verified by manager tier';
end $$;

do $$
declare v_rows int;
begin
  update public.employee_qualifications set status = 'verified' where employee_id = '00000000-0000-0000-0000-000000005491';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: direct client UPDATE of employee_qualifications succeeded (% rows)', v_rows; end if;
  raise notice 'PASS: employee_qualifications has no direct client write path (0 rows affected)';
end $$;

-- ---------------------------------------------------------------------------
-- Training: enroll, complete.

do $$
declare v_enrollment_id uuid; v_status public.training_enrollment_status;
begin
  select id, status into v_enrollment_id, v_status from public.enroll_employee_training('00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000005491');
  if v_status <> 'scheduled' then raise exception 'FAIL: expected scheduled, got %', v_status; end if;

  select status into v_status from public.complete_employee_training(v_enrollment_id, 'completed', 'Passed');
  if v_status <> 'completed' then raise exception 'FAIL: expected completed, got %', v_status; end if;
  raise notice 'PASS: training enrollment created and completed';
end $$;

-- ---------------------------------------------------------------------------
-- Performance reviews: full lifecycle including employee's own
-- acknowledgement step, and the finalisation lock.

do $$
declare v_review_id uuid; v_status public.performance_review_status;
begin
  select id, status into v_review_id, v_status from public.create_performance_review(
    '00000000-0000-0000-0000-000000005491', '00000000-0000-0000-0000-000000004901', '2026-01-01', '2026-06-30'
  );
  if v_status <> 'draft' then raise exception 'FAIL: expected draft, got %', v_status; end if;

  select status into v_status from public.advance_performance_review(v_review_id, 'manager_review', 'Solid start', null, 4.0);
  if v_status <> 'manager_review' then raise exception 'FAIL: expected manager_review, got %', v_status; end if;

  select status into v_status from public.advance_performance_review(v_review_id, 'employee_review');
  if v_status <> 'employee_review' then raise exception 'FAIL: expected employee_review, got %', v_status; end if;

  perform set_config('sebetsa.test.review_id', v_review_id::text, false);
  raise notice 'PASS: performance review advances through draft -> manager_review -> employee_review';
end $$;

-- Only the reviewed employee themselves may acknowledge.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004903","app_metadata":{"role":"site_manager"}}';

do $$
declare v_review_id uuid;
begin
  v_review_id := current_setting('sebetsa.test.review_id')::uuid;
  begin
    perform public.advance_performance_review(v_review_id, 'acknowledgement');
    raise exception 'SECURITY_FAILURE: a non-reviewee (site_manager) acknowledged someone else''s performance review';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: only-the-reviewee acknowledgement rule blocks an unrelated caller (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004902","app_metadata":{"role":"employee"}}';

do $$
declare v_review_id uuid; v_status public.performance_review_status;
begin
  v_review_id := current_setting('sebetsa.test.review_id')::uuid;
  select status into v_status from public.advance_performance_review(v_review_id, 'acknowledgement', null, 'Agreed, thank you');
  if v_status <> 'acknowledgement' then raise exception 'FAIL: expected acknowledgement, got %', v_status; end if;
  raise notice 'PASS: the reviewed employee can acknowledge their own review';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"hr_user"}}';

do $$
declare v_review_id uuid; v_status public.performance_review_status;
begin
  v_review_id := current_setting('sebetsa.test.review_id')::uuid;
  select status into v_status from public.advance_performance_review(v_review_id, 'finalized');
  if v_status <> 'finalized' then raise exception 'FAIL: expected finalized, got %', v_status; end if;

  begin
    perform public.advance_performance_review(v_review_id, 'draft');
    raise exception 'SECURITY_FAILURE: a finalized performance review was modified';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: finalized performance review is permanently locked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Development actions: manager adds, owner self-completes.

do $$
declare v_id uuid;
begin
  select id into v_id from public.add_development_action('00000000-0000-0000-0000-000000005491', 'Complete advanced first aid course', '00000000-0000-0000-0000-000000004902', '2026-12-31', null);
  perform set_config('sebetsa.test.action_id', v_id::text, false);
  raise notice 'PASS: manager can add a development action (%)', v_id;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004902","app_metadata":{"role":"employee"}}';

do $$
declare v_id uuid; v_status text;
begin
  v_id := current_setting('sebetsa.test.action_id')::uuid;
  select status into v_status from public.update_development_action_status(v_id, 'completed');
  if v_status <> 'completed' then raise exception 'FAIL: expected completed, got %', v_status; end if;
  raise notice 'PASS: the action owner can self-complete their own development action';
end $$;

-- Append-only audit check.
reset role;
reset request.jwt.claims;
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'performance_reviews' and action = 'performance_review_advanced';
  if v_count < 1 then raise exception 'FAIL: performance review advancement was not audit-logged'; end if;
  raise notice 'PASS: performance review advancement is audit-logged';
end $$;

rollback;
