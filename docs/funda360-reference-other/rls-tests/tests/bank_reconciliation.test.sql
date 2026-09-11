-- Regression suite for FND-PAY-002 (20260829290000_bank_reconciliation.sql).
-- Reuses the same School A/B fixtures as fees_adjustments_and_refunds.test.sql:
-- learner 11110000...0001 (School A) / 22220000...0001 (School B), academic
-- year aaaa1111...0001 (School A) / bbbb1111...0001 (School B),
-- finance_manager 17171717 / teacher 11111111 (School A), finance_manager
-- 16161616 (School B). Two dedicated unreconciled payments are created
-- below for this file's own matching tests, so nothing here collides with
-- other test files' own use of the shared learner/year fixtures.

do $$
declare
  v_payment_a1_id uuid;
  v_payment_a2_id uuid;
  v_payment_b_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 1500.00, current_date, 'eft')
    returning id into v_payment_a1_id;
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 2200.00, current_date, 'eft')
    returning id into v_payment_a2_id;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22220000-0000-0000-0000-000000000001', 'bbbb1111-0000-0000-0000-000000000001', 1500.00, current_date, 'eft')
    returning id into v_payment_b_id;
  execute 'reset role';

  perform set_config('app.test_payment_a1_id', v_payment_a1_id::text, false);
  perform set_config('app.test_payment_a2_id', v_payment_a2_id::text, false);
  perform set_config('app.test_payment_b_id', v_payment_b_id::text, false);
end $$;

-- ---------------------------------------------------------------------------
-- 1. finance_manager can upload a statement (import row + lines).
do $$
declare v_import_id uuid;
declare v_line1_id uuid;
declare v_error text;
declare v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.bank_reconciliation_imports (school_id, file_name)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'statement-jan-2026.csv')
      returning id into v_import_id;
    insert into public.bank_statement_lines (school_id, import_id, transaction_date, description, amount)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_import_id, current_date, 'EFT REF 001', 1500.00)
      returning id into v_line1_id;
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  perform set_config('app.test_line1_id', v_line1_id::text, false);
  call test_util.record('a finance_manager can upload a statement (import + lines)', v_ok and v_line1_id is not null, coalesce(v_error, 'line=' || v_line1_id::text));
end $$;

-- ---------------------------------------------------------------------------
-- 2. A teacher (no financial access) cannot upload a statement.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.bank_reconciliation_imports (school_id, file_name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sneaky.csv');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a teacher without financial access cannot upload a statement', v_ok, coalesce(v_error, 'insert succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. finance_manager can reconcile the line against the matching payment —
-- both sides update atomically.
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_line_status text;
declare v_payment_reconciled_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.reconcile_bank_statement_line(
      current_setting('app.test_line1_id')::uuid, current_setting('app.test_payment_a1_id')::uuid);
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';

  select status into v_line_status from public.bank_statement_lines where id = current_setting('app.test_line1_id')::uuid;
  select reconciled_at into v_payment_reconciled_at from public.learner_fee_payments where id = current_setting('app.test_payment_a1_id')::uuid;
  call test_util.record('reconciling a line sets both the line to matched and the payment reconciled_at, atomically',
    v_ok and v_line_status = 'matched' and v_payment_reconciled_at is not null,
    coalesce(v_error, 'line_status=' || coalesce(v_line_status, 'null') || ' reconciled_at=' || coalesce(v_payment_reconciled_at::text, 'null')));
end $$;

-- ---------------------------------------------------------------------------
-- 4. Reconciling an already-matched line again is rejected.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.reconcile_bank_statement_line(
      current_setting('app.test_line1_id')::uuid, current_setting('app.test_payment_a2_id')::uuid);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'already_matched:%';
  end;
  execute 'reset role';
  call test_util.record('reconciling an already-matched line again is rejected', v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. Reconciling a second line against an already-reconciled payment is
-- rejected.
do $$
declare v_error text;
declare v_ok boolean := false;
declare v_import_id uuid;
declare v_line2_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.bank_reconciliation_imports (school_id, file_name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'statement-2.csv') returning id into v_import_id;
  insert into public.bank_statement_lines (school_id, import_id, transaction_date, description, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_import_id, current_date, 'Duplicate ref', 1500.00) returning id into v_line2_id;
  begin
    perform public.reconcile_bank_statement_line(v_line2_id, current_setting('app.test_payment_a1_id')::uuid);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'already_reconciled:%';
  end;
  execute 'reset role';
  call test_util.record('reconciling a line against an already-reconciled payment is rejected', v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 6. A cross-school payment cannot be matched to a School A line.
do $$
declare v_error text;
declare v_ok boolean := false;
declare v_import_id uuid;
declare v_line_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.bank_reconciliation_imports (school_id, file_name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'statement-3.csv') returning id into v_import_id;
  insert into public.bank_statement_lines (school_id, import_id, transaction_date, description, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_import_id, current_date, 'Cross-school probe', 1500.00) returning id into v_line_id;
  begin
    perform public.reconcile_bank_statement_line(v_line_id, current_setting('app.test_payment_b_id')::uuid);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'insufficient_privilege: the payment must belong to the same school%';
  end;
  execute 'reset role';
  call test_util.record('a cross-school payment cannot be matched to a statement line', v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 7. A direct client UPDATE cannot set a line to matched, bypassing the RPC.
do $$
declare v_error text;
declare v_ok boolean := false;
declare v_import_id uuid;
declare v_line_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.bank_reconciliation_imports (school_id, file_name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'statement-4.csv') returning id into v_import_id;
  insert into public.bank_statement_lines (school_id, import_id, transaction_date, description, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_import_id, current_date, 'Direct write probe', 999.00) returning id into v_line_id;
  begin
    update public.bank_statement_lines set status = 'matched', matched_payment_id = current_setting('app.test_payment_a2_id')::uuid where id = v_line_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'insufficient_privilege: matching/unmatching%';
  end;
  execute 'reset role';
  call test_util.record('a direct client UPDATE cannot set a statement line to matched, bypassing the RPC', v_ok, coalesce(v_error, 'update succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 8. A direct client UPDATE cannot set learner_fee_payments.reconciled_at,
-- bypassing the RPC.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    update public.learner_fee_payments set reconciled_at = now() where id = current_setting('app.test_payment_a2_id')::uuid;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'insufficient_privilege: reconciled_at%';
  end;
  execute 'reset role';
  call test_util.record('a direct client UPDATE cannot set learner_fee_payments.reconciled_at, bypassing the RPC', v_ok, coalesce(v_error, 'update succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 9. A plain UPDATE marking an unmatched line as ignored succeeds (the one
-- status transition that IS a plain client write).
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_import_id uuid;
declare v_line_id uuid;
declare v_status text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.bank_reconciliation_imports (school_id, file_name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'statement-5.csv') returning id into v_import_id;
  insert into public.bank_statement_lines (school_id, import_id, transaction_date, description, amount)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_import_id, current_date, 'Bank service fee', 25.00) returning id into v_line_id;
  begin
    update public.bank_statement_lines set status = 'ignored' where id = v_line_id;
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  select status into v_status from public.bank_statement_lines where id = v_line_id;
  call test_util.record('a plain UPDATE marking an unmatched line as ignored succeeds', v_ok and v_status = 'ignored', coalesce(v_error, 'status=' || coalesce(v_status, 'null')));
end $$;

-- ---------------------------------------------------------------------------
-- 10. unreconcile_bank_statement_line() reverses both sides atomically.
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_line_status text;
declare v_payment_reconciled_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.unreconcile_bank_statement_line(current_setting('app.test_line1_id')::uuid);
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  select status into v_line_status from public.bank_statement_lines where id = current_setting('app.test_line1_id')::uuid;
  select reconciled_at into v_payment_reconciled_at from public.learner_fee_payments where id = current_setting('app.test_payment_a1_id')::uuid;
  call test_util.record('unreconciling a line clears both the line status and the payment reconciled_at',
    v_ok and v_line_status = 'unmatched' and v_payment_reconciled_at is null,
    coalesce(v_error, 'line_status=' || coalesce(v_line_status, 'null') || ' reconciled_at=' || coalesce(v_payment_reconciled_at::text, 'null')));
end $$;

-- ---------------------------------------------------------------------------
-- 11. Cross-tenant: School B's finance_manager cannot see School A's
-- imports or lines.
do $$
declare v_import_count integer;
declare v_line_count integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_import_count from public.bank_reconciliation_imports where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  select count(*) into v_line_count from public.bank_statement_lines where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('cross-tenant bank reconciliation imports/lines remain invisible', v_import_count = 0 and v_line_count = 0, 'imports=' || v_import_count || ' lines=' || v_line_count);
end $$;

-- ---------------------------------------------------------------------------
-- 12. Hard delete is impossible for either table.
do $$
declare v_deleted_imports integer;
declare v_deleted_lines integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.bank_statement_lines where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_deleted_lines = row_count;
  delete from public.bank_reconciliation_imports where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_deleted_imports = row_count;
  execute 'reset role';
  call test_util.record('hard delete of bank reconciliation imports/lines is impossible', v_deleted_lines = 0 and v_deleted_imports = 0, 'lines=' || v_deleted_lines || ' imports=' || v_deleted_imports);
end $$;

-- ---------------------------------------------------------------------------
-- 13. Every match/unmatch action is written to audit_log.
do $$
declare v_matched_count integer;
declare v_unmatched_count integer;
begin
  select count(*) into v_matched_count from public.audit_log where entity_table = 'bank_statement_lines' and action = 'bank_statement_line_matched' and entity_id = current_setting('app.test_line1_id')::uuid;
  select count(*) into v_unmatched_count from public.audit_log where entity_table = 'bank_statement_lines' and action = 'bank_statement_line_unmatched' and entity_id = current_setting('app.test_line1_id')::uuid;
  call test_util.record('every reconcile/unreconcile action is written to audit_log', v_matched_count = 1 and v_unmatched_count = 1, 'matched=' || v_matched_count || ' unmatched=' || v_unmatched_count);
end $$;
