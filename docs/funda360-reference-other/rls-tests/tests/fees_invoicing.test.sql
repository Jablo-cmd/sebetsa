-- Regression suite for 20260903090000_fees_invoicing.sql — invoices,
-- payment allocation, receipts, invoice locking, guardian visibility,
-- cross-tenant isolation.
--
-- Creates its own dedicated learners + guardian (same isolation lesson as
-- fee_overdue_reminders.test.sql). Reuses School A (aaaaaaaa…), academic
-- year aaaa1111…0001, finance_manager 17171717 (11_fees_behaviour_fixtures),
-- teacher 11111111 (02_fixtures), School B finance_manager 16161616.

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'f1110000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
     'fees-inv-guardian@schoola.test', jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('f1110000-0000-0000-0000-0000000000a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'InvoiceGuardian', 'A', 'fees-inv-guardian@schoola.test', 'guardian', 'active');

  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('f1110000-0000-0000-0000-0000000000e1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-FI01', 'ADM-A-FI01', 'Invoice', 'LearnerOne', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'f1110000-0000-0000-0000-0000000000a1', 'mother', true);

  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('f1110000-0000-0000-0000-0000000000e2', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'LRN-B-FI01', 'ADM-B-FI01', 'Invoice', 'LearnerTwoB', '2014-04-01', 'active', '2024-01-15');
end $$;

-- ---------------------------------------------------------------------------
-- 1. Draft -> issued -> allocation -> receipt.
do $$
declare
  v_invoice_id uuid := 'f1110000-0000-0000-0000-0000000000d1';
  v_payment_id uuid := 'f1110000-0000-0000-0000-0000000000d5';
  v_issued public.invoices;
  v_receipt public.fee_receipts;
  v_receipt2 public.fee_receipts;
  v_alloc numeric;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.invoices (id, school_id, learner_id, academic_year_id, notes)
  values (v_invoice_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', 'Term 1 fees');

  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, invoice_id, description, category, amount) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', v_invoice_id, 'Tuition', 'tuition', 1000),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', v_invoice_id, 'Transport', 'transport', 500);

  select * into v_issued from public.issue_fee_invoice(v_invoice_id);
  call test_util.record('issue_fee_invoice assigns a number', v_issued.invoice_number is not null, coalesce(v_issued.invoice_number, 'NULL'));
  call test_util.record('issue_fee_invoice snapshots subtotal = sum(charges)', v_issued.subtotal = 1500, 'subtotal: ' || v_issued.subtotal);
  call test_util.record('issue_fee_invoice sets status issued', v_issued.status = 'issued', v_issued.status::text);

  insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method)
  values (v_payment_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', 1200, current_date, 'eft');

  perform public.allocate_fee_payment(v_payment_id, jsonb_build_array(jsonb_build_object('invoice_id', v_invoice_id, 'amount', 900)));
  select coalesce(sum(amount), 0) into v_alloc from public.learner_fee_payment_allocations where invoice_id = v_invoice_id;
  call test_util.record('allocate_fee_payment records the allocation', v_alloc = 900, 'allocated: ' || v_alloc);

  select * into v_receipt from public.issue_fee_receipt(v_payment_id);
  call test_util.record('issue_fee_receipt assigns a receipt number', v_receipt.receipt_number is not null, coalesce(v_receipt.receipt_number, 'NULL'));
  select * into v_receipt2 from public.issue_fee_receipt(v_payment_id);
  call test_util.record('issue_fee_receipt is idempotent', v_receipt2.id = v_receipt.id, '');

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Over-allocation rejected — single payment, and cross-payment (proves
-- the check counts allocations from OTHER payments; the FOR UPDATE locks in
-- 20260903110000 make that same check concurrency-safe).
do $$
declare v_error text; v_error2 text; v_p2 uuid := 'f1110000-0000-0000-0000-0000000000d6';
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.allocate_fee_payment('f1110000-0000-0000-0000-0000000000d5',
      jsonb_build_array(jsonb_build_object('invoice_id', 'f1110000-0000-0000-0000-0000000000d1', 'amount', 99999)));
    call test_util.record('allocation exceeding the invoice total is rejected', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('allocation exceeding the invoice total is rejected', true, v_error);
  end;

  -- d5 already has 900 allocated to invoice d1 (total 1500) from test 1.
  -- A second payment trying to add 700 more (900 + 700 > 1500) must fail.
  insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method)
  values (v_p2, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', 700, current_date, 'eft');
  begin
    perform public.allocate_fee_payment(v_p2,
      jsonb_build_array(jsonb_build_object('invoice_id', 'f1110000-0000-0000-0000-0000000000d1', 'amount', 700)));
    call test_util.record('a second payment cannot push total invoice allocation over the invoice total', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error2 = message_text;
    call test_util.record('a second payment cannot push total invoice allocation over the invoice total', true, v_error2);
  end;

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2b. Gate 7: next_fee_document_number() is internal-only — an
-- authenticated client cannot call it directly (20260903110000).
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.next_fee_document_number('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'invoice');
    call test_util.record('an authenticated client cannot call next_fee_document_number', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an authenticated client cannot call next_fee_document_number', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Issued-invoice lock + void deactivates charges.
do $$
declare v_error text; v_active_after int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.learner_fee_charges set amount = 5 where invoice_id = 'f1110000-0000-0000-0000-0000000000d1' and description = 'Tuition';
    call test_util.record('a charge on an issued invoice cannot be edited directly', false, 'update succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a charge on an issued invoice cannot be edited directly', true, v_error);
  end;

  perform public.void_fee_invoice('f1110000-0000-0000-0000-0000000000d1', 'Issued in error for the regression suite');
  select count(*) into v_active_after from public.learner_fee_charges where invoice_id = 'f1110000-0000-0000-0000-0000000000d1' and active;
  call test_util.record('void_fee_invoice deactivates its line-item charges', v_active_after = 0, 'active charges: ' || v_active_after);

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Teacher: no invoice visibility, no invoice creation.
do $$
declare v_visible int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_visible from public.invoices;
  call test_util.record('a teacher sees no invoices', v_visible = 0, 'rows: ' || v_visible);

  begin
    insert into public.invoices (school_id, learner_id, academic_year_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001');
    call test_util.record('a teacher cannot create an invoice', false, 'insert succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot create an invoice', true, v_error);
  end;

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Guardian visibility: own child's issued invoices + receipts, never a draft.
do $$
declare
  v_draft_id uuid := 'f1110000-0000-0000-0000-0000000000d2';
  v_issued_id uuid := 'f1110000-0000-0000-0000-0000000000d3';
  v_guardian_issued int; v_guardian_draft int; v_guardian_receipts int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.invoices (id, school_id, learner_id, academic_year_id)
  values (v_draft_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001');
  insert into public.invoices (id, school_id, learner_id, academic_year_id)
  values (v_issued_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001');
  insert into public.learner_fee_charges (school_id, learner_id, academic_year_id, invoice_id, description, category, amount)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'f1110000-0000-0000-0000-0000000000e1', 'aaaa1111-0000-0000-0000-000000000001', v_issued_id, 'Tuition T2', 'tuition', 800);
  perform public.issue_fee_invoice(v_issued_id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('f1110000-0000-0000-0000-0000000000a1', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_guardian_issued from public.invoices where id = v_issued_id;
  select count(*) into v_guardian_draft from public.invoices where id = v_draft_id;
  select count(*) into v_guardian_receipts from public.fee_receipts where learner_id = 'f1110000-0000-0000-0000-0000000000e1';

  call test_util.record('a guardian sees their child''s issued invoice', v_guardian_issued = 1, 'rows: ' || v_guardian_issued);
  call test_util.record('a guardian does NOT see a draft invoice', v_guardian_draft = 0, 'rows: ' || v_guardian_draft);
  call test_util.record('a guardian sees their child''s receipts', v_guardian_receipts >= 1, 'rows: ' || v_guardian_receipts);

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Cross-tenant: School B finance cannot see or issue School A invoices.
do $$
declare v_visible int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_visible from public.invoices where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('School B finance cannot see School A invoices', v_visible = 0, 'rows: ' || v_visible);

  begin
    perform public.issue_fee_invoice('f1110000-0000-0000-0000-0000000000d3');
    call test_util.record('School B finance cannot issue a School A invoice', false, 'call succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B finance cannot issue a School A invoice', true, v_error);
  end;

  execute 'reset role';
end $$;
