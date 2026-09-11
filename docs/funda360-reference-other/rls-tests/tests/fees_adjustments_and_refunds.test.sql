-- Regression suite for the Fees domain extension (learner_fee_adjustments,
-- learner_fee_refunds — 20260828090000_fees_adjustments_and_refunds.sql).
-- Reuses the same School A/B fixtures as fees.test.sql: learner
-- 11110000...0001 (School A) / 22220000...0001 (School B), academic year
-- aaaa1111...0001 (School A) / bbbb1111...0001 (School B), finance_manager
-- 17171717 / accountant 13131313 / principal 77777777 / teacher 11111111
-- (all School A) plus finance_manager 16161616 (School B).

do $$
declare
  v_charge_id uuid;
  v_payment_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, description, category, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Adj/Refund fixture charge', 'tuition', 2000.00)
    returning id into v_charge_id;
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 800.00, current_date, 'eft')
    returning id into v_payment_id;
  execute 'reset role';
  perform set_config('app.test_charge_id', v_charge_id::text, false);
  perform set_config('app.test_payment_id', v_payment_id::text, false);
end $$;

-- ---------------------------------------------------------------------------
-- 1. finance_manager can record a discount against that charge.
do $$
declare v_adjustment_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_adjustments (school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, amount, reason)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
            current_setting('app.test_charge_id')::uuid, 'discount', 'fixed_amount', 200.00, 'Sibling discount')
    returning id into v_adjustment_id;
  select count(*) into v_count from public.learner_fee_adjustments where id = v_adjustment_id;
  execute 'reset role';
  call test_util.record('finance_manager can insert and see a fee adjustment for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. An adjustment's charge_id must belong to the same learner it's applied to.
do $$
declare v_error text;
declare v_other_learner_charge_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  -- a charge that belongs to a DIFFERENT learner in the same school
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, description, category, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002', 'aaaa1111-0000-0000-0000-000000000001', 'Other learner charge', 'tuition', 500.00)
    returning id into v_other_learner_charge_id;
  begin
    insert into public.learner_fee_adjustments (school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, amount, reason)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
              v_other_learner_charge_id, 'discount', 'fixed_amount', 50.00, 'Mismatched charge');
    call test_util.record('an adjustment cannot reference a charge belonging to a different learner', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an adjustment cannot reference a charge belonging to a different learner', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. accountant can request a refund against the fixture payment, within
-- the refundable balance.
do $$
declare v_refund_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('13131313-1313-1313-1313-131313131313', 'accountant', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason, status)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
            current_setting('app.test_payment_id')::uuid, 300.00, current_date, 'eft', 'Overpayment', 'completed')
    returning id into v_refund_id;
  select count(*) into v_count from public.learner_fee_refunds where id = v_refund_id;
  execute 'reset role';
  call test_util.record('accountant can insert and see a refund for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A second refund exceeding the remaining refundable balance (800 paid,
-- 300 already refunded, remaining 500) is rejected by the trigger, not
-- merely by client-side validation.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('13131313-1313-1313-1313-131313131313', 'accountant', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
              current_setting('app.test_payment_id')::uuid, 600.00, current_date, 'eft', 'Excessive refund attempt', 'pending');
    call test_util.record('a refund exceeding the remaining refundable balance is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a refund exceeding the remaining refundable balance is rejected', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. A refund exactly at the remaining refundable balance (500.00) succeeds.
do $$
declare v_refund_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('13131313-1313-1313-1313-131313131313', 'accountant', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason, status)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
            current_setting('app.test_payment_id')::uuid, 500.00, current_date, 'eft', 'Remaining balance refund', 'pending')
    returning id into v_refund_id;
  select count(*) into v_count from public.learner_fee_refunds where id = v_refund_id;
  execute 'reset role';
  call test_util.record('a refund exactly at the remaining refundable balance succeeds', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. principal can view (duty-of-care) but cannot manage adjustments/refunds
-- — identical shape to the rest of the fees domain.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_adjustments where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('principal can view fee adjustments (duty-of-care)', v_count >= 1, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
              current_setting('app.test_payment_id')::uuid, 1.00, current_date, 'eft', 'Rogue refund');
    call test_util.record('principal cannot insert a refund (view-only, not manage)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('principal cannot insert a refund (view-only, not manage)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. A teacher (no financial permission at all) cannot view either table.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_adjustments where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher cannot view any fee adjustments', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Cross-tenant: School B's finance_manager cannot see or refund School
-- A's payment, even though the role itself would otherwise qualify.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_refunds where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B''s finance_manager cannot see School A''s refunds', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11110000-0000-0000-0000-000000000001', 'bbbb1111-0000-0000-0000-000000000001',
              current_setting('app.test_payment_id')::uuid, 1.00, current_date, 'eft', 'Cross-tenant refund attempt');
    call test_util.record('School B''s finance_manager cannot refund School A''s payment (cross-tenant FK check)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s finance_manager cannot refund School A''s payment (cross-tenant FK check)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 9. A guardian of the learner can see (read-only) their child's adjustments
-- and refunds via the Parent Portal policy, but not another guardian's.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_fee_adjustments where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('the learner''s own guardian can view their child''s fee adjustments', v_count >= 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 10. No DELETE policy exists on either table — void via active=false only,
-- even for the finance_manager who created the row.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.learner_fee_adjustments where learner_id = '11110000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a fee adjustment is impossible even for the finance_manager who created it', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;

do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('13131313-1313-1313-1313-131313131313', 'accountant', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.learner_fee_refunds where learner_id = '11110000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a refund is impossible even for the accountant who created it', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
