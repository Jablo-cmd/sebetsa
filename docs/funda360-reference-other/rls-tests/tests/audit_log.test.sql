-- Regression suite for the Audit Log foundation (FND-ARCH-001,
-- 20260829090000_audit_log.sql). Reuses School A/B fixtures from
-- 02_fixtures.sql: School A id aaaaaaaa-...-aaaaaaaaaaaa, School B id
-- bbbbbbbb-...-bbbbbbbbbbbb, School A's teacher 11111111-...-11111111,
-- School A's finance_manager 17171717 / accountant 13131313, School A's
-- learner 11110000-...-0001 with a Term 1 charge/payment already present
-- from earlier test files, and platform admin 44444444-...-44444444.
--
-- Creates its own dedicated profile (never reused/mutated by any other
-- test file) as the admin_update_user_role() target, rather than touching
-- a shared fixture identity another test file's later assertions might
-- depend on.

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a',
     'authenticated', 'authenticated', 'audit-log-target@schoola.test',
     jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Audit', 'Target', 'audit-log-target@schoola.test', 'teacher', 'active');
end $$;

-- Who is School A's school_owner? Reuse the id from 02_fixtures.sql via a
-- lookup rather than hard-coding it a second time, in case that file's own
-- id ever changes.
do $$
declare v_owner_id uuid;
begin
  select id into v_owner_id from public.profiles where tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and role = 'school_owner' limit 1;
  perform set_config('app.school_a_owner_id', v_owner_id::text, false);
end $$;

-- ---------------------------------------------------------------------------
-- 1. A role change via admin_update_user_role writes exactly one audit_log
-- row, with correct before/after.
do $$
declare v_count int;
declare v_before jsonb;
declare v_after jsonb;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims(current_setting('app.school_a_owner_id')::uuid, 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform public.admin_update_user_role('9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a', 'principal');
  select count(*) into v_count
    from public.audit_log
    where entity_table = 'profiles' and entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a' and action = 'role_changed';
  select before, after into v_before, v_after
    from public.audit_log
    where entity_table = 'profiles' and entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a' and action = 'role_changed'
    limit 1;
  execute 'reset role';
  call test_util.record('admin_update_user_role writes exactly one role_changed audit_log row', v_count = 1, 'rows: ' || v_count);
  call test_util.record('the audit_log row records the correct before/after role',
    v_before->>'role' = 'teacher' and v_after->>'role' = 'principal',
    'before=' || v_before::text || ' after=' || v_after::text);
end $$;

-- ---------------------------------------------------------------------------
-- 2. School A's school_owner can see that audit_log row.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims(current_setting('app.school_a_owner_id')::uuid, 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.audit_log where entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a';
  execute 'reset role';
  call test_util.record('school_owner can view their own school''s audit_log', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher (no audit-log visibility role) sees none of it.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.audit_log where entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a';
  execute 'reset role';
  call test_util.record('a teacher cannot view audit_log at all', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant: School B cannot see School A's audit_log rows, even as
-- a school_owner.
do $$
declare v_count int;
declare v_owner_b uuid;
begin
  select id into v_owner_b from public.profiles where tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and role = 'school_owner' limit 1;
  perform set_config('request.jwt.claims',
    test_util.jwt_claims(v_owner_b, 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.audit_log where entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a';
  execute 'reset role';
  call test_util.record('School B''s school_owner cannot see School A''s audit_log rows', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. A platform admin sees the row regardless of tenant.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.audit_log where entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a';
  execute 'reset role';
  call test_util.record('a platform admin can view any tenant''s audit_log', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. No authenticated caller — not even a school_owner — can insert into
-- audit_log directly. Only the SECURITY DEFINER write path can.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims(current_setting('app.school_a_owner_id')::uuid, 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.audit_log (school_id, actor_profile_id, action, entity_table, entity_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_setting('app.school_a_owner_id')::uuid, 'forged_entry', 'profiles', '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a');
    call test_util.record('a client cannot insert directly into audit_log', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a client cannot insert directly into audit_log', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. A fee refund (no RPC front door — direct RLS-gated insert, per this
-- session's own Finance work) is captured by the allowlisted trigger, not
-- silently missed.
do $$
declare v_charge_id uuid;
declare v_payment_id uuid;
declare v_refund_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 900.00, current_date, 'eft')
    returning id into v_payment_id;
  insert into public.learner_fee_refunds (school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reason, status)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', v_payment_id, 100.00, current_date, 'eft', 'Audit log trigger test', 'completed')
    returning id into v_refund_id;
  execute 'reset role';
  -- finance_manager has no audit_log SELECT visibility at all (only
  -- school_owner/principal/platform admin do) — that is itself correct
  -- per this migration's RLS policy, not what's under test here, so verify
  -- as school_owner instead of conflating "wrote the row" with "this
  -- particular caller can read it back".
  perform set_config('request.jwt.claims',
    test_util.jwt_claims(current_setting('app.school_a_owner_id')::uuid, 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.audit_log where entity_table = 'learner_fee_refunds' and entity_id = v_refund_id and action = 'insert_learner_fee_refunds';
  execute 'reset role';
  call test_util.record('a fee refund insert (no RPC front door) is still captured via the allowlisted trigger', v_count = 1, 'rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. No UPDATE/DELETE policy exists on audit_log — the trail cannot be
-- altered or erased even by a platform admin.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  update public.audit_log set action = 'tampered' where entity_id = '9a9a9a9a-9a9a-9a9a-9a9a-9a9a9a9a9a9a';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('audit_log rows cannot be altered even by a platform admin (no UPDATE policy)', v_updated = 0, 'rows updated: ' || v_updated);
end $$;
