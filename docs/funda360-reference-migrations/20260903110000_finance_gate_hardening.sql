-- Finance domain — completion-gate hardening (additive, no schema change)
--
-- Two findings from the Finance acceptance gate, fixed here via
-- `create or replace function` + `revoke` (the shipped invoicing/gateway
-- migration files are not edited — same convention as
-- 20260829090000_audit_log.sql re-declaring existing RPCs):
--
--   Gate 6 — payment allocation must be impossible to over-allocate under
--   CONCURRENT requests. The prior bodies read `sum(existing allocations)`
--   without locking the invoice row, so two transactions allocating
--   different payments to the same invoice could both pass the
--   "<= invoice total" check and jointly exceed it. Neither corrupts the
--   derived account balance (allocations are pure attribution; the
--   payments are real regardless), but the gate requires it be impossible.
--   Fix: allocate_fee_payment() now locks the payment row FOR UPDATE
--   (serialising same-payment writes) and each target invoice FOR UPDATE
--   in invoice_id order (serialising same-invoice writes, ordered to avoid
--   deadlock); settle_payment_intent() now locks its single target invoice
--   FOR UPDATE before measuring existing allocations.
--
--   Gate 7 — invoice/receipt numbering must not be client-manipulable.
--   next_fee_document_number() and expire_stale_payment_intents() are
--   internal-only (called from other SECURITY DEFINER bodies / cron), and
--   were already `revoke ... from public`. This adds the explicit
--   `revoke ... from authenticated` that 20260822020000_
--   trigger_function_authenticated_revoke.sql established as the pattern —
--   belt-and-braces against a project whose Data API is configured to
--   auto-expose new functions.

-- ---------------------------------------------------------------------------
-- Gate 7: internal-only functions are not directly callable by a client.

revoke execute on function public.next_fee_document_number(uuid, text) from authenticated;
revoke execute on function public.expire_stale_payment_intents() from authenticated;

-- ---------------------------------------------------------------------------
-- Gate 6: allocate_fee_payment() — same body as
-- 20260903090000_fees_invoicing.sql plus row locks.

create or replace function public.allocate_fee_payment(p_payment_id uuid, p_allocations jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.learner_fee_payments;
  v_alloc jsonb;
  v_invoice_id uuid;
  v_amount numeric(12, 2);
  v_total_alloc numeric(12, 2) := 0;
  v_invoice record;
  v_already numeric(12, 2);
begin
  -- Lock the payment row: serialises concurrent allocate calls for the
  -- same payment (each fully replaces the set).
  select * into v_payment from public.learner_fee_payments where id = p_payment_id for update;
  if not found then
    raise exception 'not_found: no payment %', p_payment_id;
  end if;
  if not public.can_manage_learner_financial(v_payment.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'invalid_argument: allocations must be a JSON array of {invoice_id, amount}';
  end if;

  delete from public.learner_fee_payment_allocations where payment_id = p_payment_id;

  -- Ordered by invoice_id so concurrent calls acquire invoice locks in the
  -- same order — no deadlock cycle.
  for v_alloc in
    select value from jsonb_array_elements(p_allocations) as t(value)
    order by (value ->> 'invoice_id')
  loop
    v_invoice_id := (v_alloc ->> 'invoice_id')::uuid;
    v_amount := round((v_alloc ->> 'amount')::numeric, 2);
    if v_amount <= 0 then
      raise exception 'invalid_argument: allocation amount must be positive';
    end if;

    -- Lock the invoice: serialises concurrent allocations (from other
    -- payments, or from settle_payment_intent) against the same invoice,
    -- so the sum-vs-total check below cannot race.
    perform 1 from public.invoices where id = v_invoice_id for update;

    select id, school_id, learner_id, total into v_invoice
      from public.invoices where id = v_invoice_id;
    if not found then
      raise exception 'not_found: no invoice %', v_invoice_id;
    end if;
    if v_invoice.school_id is distinct from v_payment.school_id then
      raise exception 'insufficient_privilege: invoice must belong to the same school as the payment';
    end if;
    if v_invoice.learner_id is distinct from v_payment.learner_id then
      raise exception 'insufficient_privilege: invoice must belong to the same learner as the payment';
    end if;

    select coalesce(sum(amount), 0) into v_already
      from public.learner_fee_payment_allocations
      where invoice_id = v_invoice_id and payment_id <> p_payment_id;
    if v_already + v_amount > v_invoice.total then
      raise exception 'invalid_argument: allocations to invoice % (% + %) exceed its total %', v_invoice_id, v_already, v_amount, v_invoice.total;
    end if;

    insert into public.learner_fee_payment_allocations (school_id, payment_id, invoice_id, amount, created_by)
    values (v_payment.school_id, p_payment_id, v_invoice_id, v_amount, auth.uid());

    v_total_alloc := v_total_alloc + v_amount;
  end loop;

  if v_total_alloc > v_payment.amount then
    raise exception 'invalid_argument: total allocations % exceed the payment amount %', v_total_alloc, v_payment.amount;
  end if;

  perform public.write_audit_log(
    v_payment.school_id, auth.uid(), 'payment_allocated', 'learner_fee_payments', p_payment_id,
    null, jsonb_build_object('allocations', p_allocations, 'total_allocated', v_total_alloc)
  );
end;
$$;

comment on function public.allocate_fee_payment(uuid, jsonb) is
  'Replaces the entire allocation set for one payment atomically, locking the payment and each target invoice FOR UPDATE. Enforces: each invoice same school + same learner as the payment; per-invoice allocations never exceed the invoice total (concurrency-safe); total allocations never exceed the payment amount. Pass [] to clear all allocations.';

revoke execute on function public.allocate_fee_payment(uuid, jsonb) from public;
revoke execute on function public.allocate_fee_payment(uuid, jsonb) from authenticated;
grant execute on function public.allocate_fee_payment(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Gate 6: settle_payment_intent() — same body as
-- 20260903100000_payment_gateway.sql plus a FOR UPDATE lock on the target
-- invoice before measuring existing allocations (step 7).

create or replace function public.settle_payment_intent(
  p_provider          public.payment_provider,
  p_mode              public.payment_mode,
  p_provider_event_id text,
  p_reference         text,
  p_provider_reference text,
  p_amount            numeric,
  p_outcome           text,
  p_signature_valid   boolean,
  p_payload           jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_intent public.payment_intents;
  v_amount numeric(12, 2) := round(p_amount, 2);
  v_payment_id uuid;
  v_invoice record;
  v_allocated numeric(12, 2);
  v_alloc_amount numeric(12, 2);
  v_guardian record;
  v_learner record;
begin
  insert into public.payment_webhook_events (provider, mode, provider_event_id, signature_valid, status_reported, payload)
  values (p_provider, p_mode, p_provider_event_id, p_signature_valid, p_outcome, p_payload)
  on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return jsonb_build_object('result', 'duplicate_ignored');
  end if;

  if not p_signature_valid then
    update public.payment_webhook_events
      set processed_at = now(), processing_error = 'signature_invalid'
      where id = v_event_id;
    return jsonb_build_object('result', 'signature_invalid');
  end if;

  select * into v_intent from public.payment_intents where reference = p_reference for update;
  if not found then
    update public.payment_webhook_events
      set processed_at = now(), processing_error = 'unknown_reference'
      where id = v_event_id;
    return jsonb_build_object('result', 'unknown_reference');
  end if;

  update public.payment_webhook_events
    set school_id = v_intent.school_id, intent_id = v_intent.id
    where id = v_event_id;

  if v_intent.status in ('succeeded', 'failed', 'cancelled', 'expired') then
    update public.payment_webhook_events set processed_at = now(), processing_error = 'intent_already_terminal' where id = v_event_id;
    return jsonb_build_object('result', 'already_' || v_intent.status);
  end if;

  if p_outcome <> 'succeeded' then
    update public.payment_intents
      set status = case p_outcome when 'cancelled' then 'cancelled'::public.payment_intent_status
                                  when 'expired' then 'expired'::public.payment_intent_status
                                  else 'failed'::public.payment_intent_status end,
          failure_reason = p_outcome,
          provider_reference = p_provider_reference,
          raw_result = p_payload,
          completed_at = now()
      where id = v_intent.id;
    update public.payment_webhook_events set processed_at = now() where id = v_event_id;
    perform public.write_audit_log(v_intent.school_id, null, 'payment_intent_' || p_outcome, 'payment_intents', v_intent.id, null, p_payload);
    return jsonb_build_object('result', p_outcome);
  end if;

  if v_amount <> v_intent.amount then
    update public.payment_intents
      set status = 'failed', failure_reason = 'amount_mismatch', provider_reference = p_provider_reference, raw_result = p_payload, completed_at = now()
      where id = v_intent.id;
    update public.payment_webhook_events set processed_at = now(), processing_error = 'amount_mismatch' where id = v_event_id;
    perform public.write_audit_log(
      v_intent.school_id, null, 'payment_amount_mismatch', 'payment_intents', v_intent.id,
      jsonb_build_object('expected', v_intent.amount), jsonb_build_object('reported', v_amount)
    );
    return jsonb_build_object('result', 'amount_mismatch');
  end if;

  insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method, reference, notes)
  select v_intent.school_id, v_intent.learner_id,
         coalesce(
           (select academic_year_id from public.invoices where id = v_intent.invoice_id),
           (select id from public.academic_years where school_id = v_intent.school_id and is_active order by start_date desc limit 1),
           (select id from public.academic_years where school_id = v_intent.school_id order by start_date desc limit 1)
         ),
         v_intent.amount, current_date, 'card',
         coalesce(p_provider_reference, p_reference),
         'Online payment via ' || p_provider::text || ' (' || p_mode::text || ')'
  returning id into v_payment_id;

  if v_intent.invoice_id is not null then
    -- Lock the invoice before measuring existing allocations — serialises
    -- against a concurrent settle / allocate_fee_payment on the same invoice.
    perform 1 from public.invoices where id = v_intent.invoice_id for update;
    select total into v_invoice from public.invoices where id = v_intent.invoice_id;
    select coalesce(sum(amount), 0) into v_allocated
      from public.learner_fee_payment_allocations where invoice_id = v_intent.invoice_id;
    v_alloc_amount := least(v_intent.amount, v_invoice.total - v_allocated);
    if v_alloc_amount > 0 then
      insert into public.learner_fee_payment_allocations (school_id, payment_id, invoice_id, amount)
      values (v_intent.school_id, v_payment_id, v_intent.invoice_id, v_alloc_amount);
    end if;
  end if;

  insert into public.fee_receipts (school_id, learner_id, payment_id, receipt_number, issued_by)
  values (v_intent.school_id, v_intent.learner_id, v_payment_id,
          public.next_fee_document_number(v_intent.school_id, 'receipt'), null);

  update public.payment_intents
    set status = 'succeeded', payment_id = v_payment_id, provider_reference = p_provider_reference, raw_result = p_payload, completed_at = now()
    where id = v_intent.id;
  update public.payment_webhook_events set processed_at = now() where id = v_event_id;

  perform public.write_audit_log(
    v_intent.school_id, null, 'gateway_payment_settled', 'payment_intents', v_intent.id,
    null, jsonb_build_object('payment_id', v_payment_id, 'amount', v_intent.amount, 'provider', p_provider)
  );

  select first_name, last_name into v_learner from public.learners where id = v_intent.learner_id;
  for v_guardian in select guardian_profile_id from public.learner_guardians where learner_id = v_intent.learner_id
  loop
    perform public.create_notification(
      v_guardian.guardian_profile_id, 'payment_received', 'Payment received',
      'We received your payment of R' || to_char(v_intent.amount, 'FM999999990.00') || ' for '
        || coalesce(v_learner.first_name, '') || ' ' || coalesce(v_learner.last_name, '') || '. A receipt is available.',
      v_intent.school_id, 'payment_intents', v_intent.id, '/parent/fees'
    );
  end loop;

  return jsonb_build_object('result', 'succeeded', 'payment_id', v_payment_id);
end;
$$;

revoke execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) from public;
revoke execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) from authenticated;
grant execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) to service_role;
