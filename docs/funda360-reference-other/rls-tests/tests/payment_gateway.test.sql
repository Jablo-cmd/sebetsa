-- Regression suite for 20260903100000_payment_gateway.sql —
-- payment_gateway_configs RLS, create_payment_intent authorization,
-- settle_payment_intent (service_role) idempotency / signature / amount
-- checks, and webhook-event visibility.
--
-- Dedicated learners + guardian. Reuses School A (aaaaaaaa…), year
-- aaaa1111…0001, finance_manager 17171717, School B finance_manager
-- 16161616 and School B learner via 05_learner_fixtures (22220000…0001).

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'f2220000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
     'pay-gw-guardian@schoola.test', jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('f2220000-0000-0000-0000-0000000000a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'PayGw', 'Guardian', 'pay-gw-guardian@schoola.test', 'guardian', 'active');
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('f2220000-0000-0000-0000-0000000000e1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-PG01', 'ADM-A-PG01', 'PayGw', 'LearnerOne', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f2220000-0000-0000-0000-0000000000e1', 'f2220000-0000-0000-0000-0000000000a1', 'mother', true);
end $$;

-- ---------------------------------------------------------------------------
-- 1. Config: finance manages it; a guardian cannot read it.
do $$
declare v_visible int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.payment_gateway_configs (school_id, provider, mode, enabled, merchant_config)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'payfast', 'test', false, '{"merchant_id":"10000100"}');
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f2220000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_visible from public.payment_gateway_configs;
  call test_util.record('a guardian cannot read payment_gateway_configs', v_visible = 0, 'rows: ' || v_visible);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. create_payment_intent: rejected while the gateway is disabled.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f2220000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.create_payment_intent('f2220000-0000-0000-0000-0000000000e1', 100, null, 'https://x/r', 'https://x/c');
    call test_util.record('create_payment_intent rejected when the gateway is disabled', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('create_payment_intent rejected when the gateway is disabled', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Enable the gateway. A guardian can start a payment for their own
-- child; a School B guardian cannot; over-invoice amount is rejected.
do $$
declare
  v_invoice_id uuid := 'f2220000-0000-0000-0000-0000000000d1';
  v_intent public.payment_intents;
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.payment_gateway_configs set enabled = true where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  insert into public.invoices (id, school_id, learner_id, academic_year_id)
  values (v_invoice_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f2220000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001');
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, invoice_id, description, category, amount)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f2220000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', v_invoice_id, 'Tuition', 'tuition', 500);
  perform public.issue_fee_invoice(v_invoice_id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f2220000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select * into v_intent from public.create_payment_intent('f2220000-0000-0000-0000-0000000000e1', 500, v_invoice_id, 'https://x/r', 'https://x/c');
  call test_util.record('a guardian can start a payment for their own child''s invoice', v_intent.status = 'created' and v_intent.amount = 500, v_intent.reference);

  begin
    perform public.create_payment_intent('f2220000-0000-0000-0000-0000000000e1', 5000, v_invoice_id, 'https://x/r', 'https://x/c');
    call test_util.record('a payment above the invoice balance is rejected', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a payment above the invoice balance is rejected', true, v_error);
  end;

  execute 'reset role';

  -- School B guardian (parent.b1 18181818 from 13_parent_portal_fixtures)
  -- cannot pay for a School A learner.
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('18181818-1818-1818-1818-181818181818', 'parent', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.create_payment_intent('f2220000-0000-0000-0000-0000000000e1', 100, null, 'https://x/r', 'https://x/c');
    call test_util.record('a cross-tenant guardian cannot start a payment', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a cross-tenant guardian cannot start a payment', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. settle_payment_intent (service_role): signature invalid is recorded
-- but never settles.
do $$
declare v_ref text; v_result jsonb; v_intent_status text;
begin
  select reference into v_ref from public.payment_intents
    where learner_id = 'f2220000-0000-0000-0000-0000000000e1' and amount = 500 order by created_at desc limit 1;

  execute 'set local role service_role';
  select public.settle_payment_intent('payfast', 'test', 'evt-sig-bad', v_ref, 'pf-1', 500, 'succeeded', false, '{}'::jsonb) into v_result;
  execute 'reset role';

  select status into v_intent_status from public.payment_intents where reference = v_ref;
  call test_util.record('settle: signature_valid=false does not settle the intent', v_intent_status = 'created' and v_result ->> 'result' = 'signature_invalid', v_result::text);
end $$;

-- ---------------------------------------------------------------------------
-- 5. settle_payment_intent: valid success books a card payment, allocates
-- it to the invoice, issues a receipt, and marks the intent succeeded.
-- A duplicate event is a no-op.
do $$
declare
  v_ref text;
  v_result jsonb;
  v_dup jsonb;
  v_intent public.payment_intents;
  v_payments int;
  v_alloc numeric;
  v_receipts int;
begin
  select reference into v_ref from public.payment_intents
    where learner_id = 'f2220000-0000-0000-0000-0000000000e1' and amount = 500 order by created_at desc limit 1;

  execute 'set local role service_role';
  select public.settle_payment_intent('payfast', 'test', 'evt-ok-1', v_ref, 'pf-ok-1', 500, 'succeeded', true, '{"pf":"ok"}'::jsonb) into v_result;
  select public.settle_payment_intent('payfast', 'test', 'evt-ok-1', v_ref, 'pf-ok-1', 500, 'succeeded', true, '{"pf":"ok"}'::jsonb) into v_dup;
  execute 'reset role';

  select * into v_intent from public.payment_intents where reference = v_ref;
  select count(*) into v_payments from public.learner_fee_payments where learner_id = 'f2220000-0000-0000-0000-0000000000e1' and active and method = 'card';
  select coalesce(sum(amount), 0) into v_alloc from public.learner_fee_payment_allocations where invoice_id = 'f2220000-0000-0000-0000-0000000000d1';
  select count(*) into v_receipts from public.fee_receipts where learner_id = 'f2220000-0000-0000-0000-0000000000e1';

  call test_util.record('settle: a valid success marks the intent succeeded', v_intent.status = 'succeeded' and v_intent.payment_id is not null, v_result::text);
  call test_util.record('settle: exactly one card payment is booked', v_payments = 1, 'payments: ' || v_payments);
  call test_util.record('settle: the payment is allocated to the invoice', v_alloc = 500, 'allocated: ' || v_alloc);
  call test_util.record('settle: a receipt is issued', v_receipts = 1, 'receipts: ' || v_receipts);
  call test_util.record('settle: a duplicate provider_event_id is ignored', v_dup ->> 'result' = 'duplicate_ignored', v_dup::text);
end $$;

-- ---------------------------------------------------------------------------
-- 6. settle_payment_intent: amount mismatch fails the intent, books nothing.
do $$
declare
  v_invoice_id uuid := 'f2220000-0000-0000-0000-0000000000d2';
  v_intent public.payment_intents;
  v_result jsonb;
  v_status text;
  v_payments_before int;
  v_payments_after int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.invoices (id, school_id, learner_id, academic_year_id)
  values (v_invoice_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f2220000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001');
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, invoice_id, description, category, amount)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f2220000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', v_invoice_id, 'Tuition', 'tuition', 300);
  perform public.issue_fee_invoice(v_invoice_id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f2220000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select * into v_intent from public.create_payment_intent('f2220000-0000-0000-0000-0000000000e1', 300, v_invoice_id, 'https://x/r', 'https://x/c');
  execute 'reset role';

  select count(*) into v_payments_before from public.learner_fee_payments where learner_id = 'f2220000-0000-0000-0000-0000000000e1' and active;

  execute 'set local role service_role';
  select public.settle_payment_intent('payfast', 'test', 'evt-mismatch', v_intent.reference, 'pf-x', 999, 'succeeded', true, '{}'::jsonb) into v_result;
  execute 'reset role';

  select status into v_status from public.payment_intents where id = v_intent.id;
  select count(*) into v_payments_after from public.learner_fee_payments where learner_id = 'f2220000-0000-0000-0000-0000000000e1' and active;

  call test_util.record('settle: an amount mismatch fails the intent', v_status = 'failed' and v_result ->> 'result' = 'amount_mismatch', v_result::text);
  call test_util.record('settle: an amount mismatch books no payment', v_payments_after = v_payments_before, 'before: ' || v_payments_before || ' after: ' || v_payments_after);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Webhook events: finance can read their own school's; a guardian cannot.
do $$
declare v_finance_visible int; v_guardian_visible int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_finance_visible from public.payment_webhook_events where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f2220000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_guardian_visible from public.payment_webhook_events;
  execute 'reset role';

  call test_util.record('finance can read their school''s webhook events', v_finance_visible >= 1, 'rows: ' || v_finance_visible);
  call test_util.record('a guardian cannot read webhook events', v_guardian_visible = 0, 'rows: ' || v_guardian_visible);
end $$;
