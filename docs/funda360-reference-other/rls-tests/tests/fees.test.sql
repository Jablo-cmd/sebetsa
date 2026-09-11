-- Regression suite for the Fees domain (fee_structures, learner_fee_charges,
-- learner_fee_payments). Uses School A/B, learner 11110000...0001 (School
-- A) / 22220000...0001 (School B), academic year aaaa1111...0001 (School A)
-- / bbbb1111...0001 (School B) from earlier fixtures, and finance_manager
-- 17171717 / accountant 13131313 / principal 77777777 / teacher 11111111
-- (all School A) plus finance_manager 16161616 (School B) from
-- 11_fees_behaviour_fixtures.sql.

-- ---------------------------------------------------------------------------
-- 1. finance_manager can insert a charge for a learner in their own school —
-- exercises learner_fee_charges_validate_tenant()'s SECURITY DEFINER read of
-- `learners`.
do $$
declare v_charge_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, description, category, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Term 1 Tuition', 'tuition', 1200.00)
    returning id into v_charge_id;
  select count(*) into v_count from public.learner_fee_charges where id = v_charge_id;
  execute 'reset role';
  call test_util.record('finance_manager can insert and see a fee charge for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. accountant can record a payment for the same learner.
do $$
declare v_payment_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('13131313-1313-1313-1313-131313131313', 'accountant', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 500.00, current_date, 'eft')
    returning id into v_payment_id;
  select count(*) into v_count from public.learner_fee_payments where id = v_payment_id;
  execute 'reset role';
  call test_util.record('accountant can insert and see a fee payment for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. principal can view (duty-of-care) but cannot manage — matches the
-- medical-information exception shape exactly.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_charges where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('principal can view fee charges (duty-of-care)', v_count >= 1, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, description, category, amount)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Rogue charge', 'other', 1.00);
    call test_util.record('principal cannot insert a fee charge (view-only, not manage)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('principal cannot insert a fee charge (view-only, not manage)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (no financial permission at all) cannot view or insert.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_charges where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher cannot view any fee charges', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's finance_manager cannot see or charge School
-- A's learner, even though the role itself would otherwise qualify.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_charges where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B''s finance_manager cannot see School A''s fee charges', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, description, category, amount)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11110000-0000-0000-0000-000000000001', 'bbbb1111-0000-0000-0000-000000000001', 'Cross-tenant charge', 'other', 1.00);
    call test_util.record('School B''s finance_manager cannot charge School A''s learner (cross-tenant FK check)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s finance_manager cannot charge School A''s learner (cross-tenant FK check)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. A platform admin sees every school's fee charges.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_charges;
  execute 'reset role';
  call test_util.record('a platform admin sees fee charges across tenants', v_count >= 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. finance_manager can resolve "the current academic year" (needed by the
-- frontend to submit a charge/payment at all) despite holding no general
-- academic.view — the narrow academic_years_select_for_domain_roles policy,
-- not can_view_academic(). Found during live UI verification: without this,
-- AcademicProvider could never load any academic_years row for
-- finance_manager, silently disabling their "Add charge"/"Record payment"
-- actions (they render, but have no academic_year_id to submit).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('finance_manager can resolve the current academic year', v_count >= 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. The academic_years fix is narrowly scoped — finance_manager still
-- cannot see the academic *structure* (grades) built under that year;
-- academic.view was never granted to them.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.grades where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('finance_manager still cannot see grades (academic_years fix stayed narrow)', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 9. No DELETE policy exists — a mismarked charge is voided (active=false),
-- never hard-deleted, even by the finance_manager who created it.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.learner_fee_charges where learner_id = '11110000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a fee charge is impossible even for the finance_manager who created it', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
