-- Online Payment Gateway — provider-agnostic architecture (spec 5, FND-PAY-001)
--
-- This is the "build the complete integration architecture, make production
-- require the real credentials" case from spec 64. Everything here is real
-- and exercised by tests; what it cannot do without a merchant account is
-- complete a live charge. The design keeps the finance domain free of any
-- single provider:
--
--   payment_gateway_configs  — per school: which provider, test/live mode,
--                              and the provider's NON-SECRET identifiers
--                              (PayFast merchant_id, Ozow site code, ...).
--                              Secrets (passphrases, private keys, API
--                              secrets) are NEVER stored here or anywhere
--                              in Postgres — they live only in the Edge
--                              Function environment (see
--                              supabase/functions/_shared/providers/*).
--   payment_intents          — one attempt to pay a specific amount
--                              (optionally against an invoice). Created by
--                              a guardian or finance user via
--                              create_payment_intent(); only ever moved to
--                              a terminal state by settle_payment_intent(),
--                              which is callable by service_role only (the
--                              webhook Edge Function), never by a client.
--   payment_webhook_events   — every inbound provider callback, with its
--                              signature-validity verdict and a
--                              (provider, provider_event_id) uniqueness
--                              constraint that makes duplicate webhook
--                              delivery a no-op.
--
-- NEVER TRUST THE CLIENT: a browser returning from the provider's payment
-- page proves nothing. A payment_intent becomes 'succeeded' only when
-- settle_payment_intent() is called by the webhook handler with a
-- signature-valid, amount-matching provider event. The return_url handler
-- in the SPA only ever *polls* intent status.

create type public.payment_provider as enum ('payfast', 'ozow', 'peach', 'yoco', 'netcash');

create type public.payment_mode as enum ('test', 'live');

create type public.payment_intent_status as enum ('created', 'processing', 'succeeded', 'failed', 'cancelled', 'expired');

-- ---------------------------------------------------------------------------
-- 1. payment_gateway_configs — per-school provider selection + public config.

create table public.payment_gateway_configs (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  provider          public.payment_provider not null,
  mode              public.payment_mode not null default 'test',
  enabled           boolean not null default false,
  merchant_config   jsonb not null default '{}'::jsonb,
  secret_last_set_at timestamptz,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (school_id)
);

comment on table public.payment_gateway_configs is 'One payment provider per school. merchant_config holds ONLY non-secret identifiers (e.g. {"merchant_id":"10000100"} for PayFast, {"site_code":"TSTSTORE1"} for Ozow). Provider secrets live exclusively in the Edge Function environment — secret_last_set_at is a human breadcrumb that someone has configured them, not the secret itself.';
comment on column public.payment_gateway_configs.enabled is 'A school with enabled=false (or no row at all) cannot initiate online payments — create_payment_intent() rejects it and the Parent Portal "Pay now" button reports that online payment is unavailable rather than failing opaquely.';

create index payment_gateway_configs_school_id_idx on public.payment_gateway_configs (school_id);

create trigger payment_gateway_configs_set_updated_at
  before update on public.payment_gateway_configs
  for each row execute function public.set_updated_at();

create trigger payment_gateway_configs_set_created_updated_by
  before insert or update on public.payment_gateway_configs
  for each row execute function public.set_created_updated_by();

-- ---------------------------------------------------------------------------
-- 2. payment_intents.

create table public.payment_intents (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  learner_id         uuid not null references public.learners (id) on delete cascade,
  invoice_id         uuid references public.invoices (id) on delete set null,
  provider           public.payment_provider not null,
  mode               public.payment_mode not null,
  amount             numeric(12, 2) not null check (amount > 0),
  currency           text not null default 'ZAR' check (char_length(currency) = 3),
  status             public.payment_intent_status not null default 'created',
  reference          text not null,
  provider_reference text,
  idempotency_key    text not null,
  return_url         text,
  cancel_url         text,
  payment_id         uuid references public.learner_fee_payments (id) on delete set null,
  failure_reason     text,
  raw_request        jsonb,
  raw_result         jsonb,
  created_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  completed_at       timestamptz,
  unique (reference),
  unique (idempotency_key)
);

comment on table public.payment_intents is 'One attempt to pay p_amount online, optionally against an invoice. `reference` is the merchant reference we hand the provider and match their callback on. Status is client-readable but client-immutable — only settle_payment_intent() (service_role) writes a terminal status, and only for a signature-valid, amount-matching provider event.';
comment on column public.payment_intents.payment_id is 'The learner_fee_payments row created when this intent succeeded. NULL until then. Wiring the online payment into the same ledger every other payment uses — no parallel money-of-record.';

create index payment_intents_school_id_idx on public.payment_intents (school_id);
create index payment_intents_learner_id_idx on public.payment_intents (learner_id);
create index payment_intents_invoice_id_idx on public.payment_intents (invoice_id);
create index payment_intents_status_idx on public.payment_intents (school_id, status);

create trigger payment_intents_set_updated_at
  before update on public.payment_intents
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. payment_webhook_events — inbound callbacks, dedupe + forensic record.

create table public.payment_webhook_events (
  id                 uuid primary key default gen_random_uuid(),
  provider           public.payment_provider not null,
  mode               public.payment_mode not null,
  provider_event_id  text not null,
  school_id          uuid references public.schools (id) on delete set null,
  intent_id          uuid references public.payment_intents (id) on delete set null,
  signature_valid    boolean not null,
  status_reported    text,
  payload            jsonb not null,
  processing_error   text,
  received_at        timestamptz not null default now(),
  processed_at       timestamptz,
  unique (provider, provider_event_id)
);

comment on table public.payment_webhook_events is 'Every inbound provider webhook. The (provider, provider_event_id) unique constraint is the duplicate-delivery guard — settle_payment_intent() inserts here first and treats a conflict as "already handled, do nothing". signature_valid=false rows are retained deliberately: a stream of them is an attack signal.';

create index payment_webhook_events_school_id_idx on public.payment_webhook_events (school_id);
create index payment_webhook_events_intent_id_idx on public.payment_webhook_events (intent_id);
create index payment_webhook_events_received_at_idx on public.payment_webhook_events (received_at);

-- ---------------------------------------------------------------------------
-- 4. RLS.

alter table public.payment_gateway_configs enable row level security;
alter table public.payment_gateway_configs force row level security;
alter table public.payment_intents enable row level security;
alter table public.payment_intents force row level security;
alter table public.payment_webhook_events enable row level security;
alter table public.payment_webhook_events force row level security;

-- Config: finance-tier only. Guardians must never see merchant identifiers.
create policy payment_gateway_configs_select on public.payment_gateway_configs
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy payment_gateway_configs_insert on public.payment_gateway_configs
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy payment_gateway_configs_update on public.payment_gateway_configs
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

-- Intents: finance sees all for the school; a guardian sees their own
-- child's. No client INSERT/UPDATE — create_payment_intent() /
-- settle_payment_intent() only.
create policy payment_intents_select on public.payment_intents
  for select to authenticated using (
    public.can_view_learner_financial(school_id) or public.is_learner_guardian(learner_id)
  );

-- Webhook events: finance / platform admin read-only forensic access.
create policy payment_webhook_events_select on public.payment_webhook_events
  for select to authenticated using (
    public.is_platform_admin()
    or (school_id is not null and public.can_view_learner_financial(school_id))
  );

-- ---------------------------------------------------------------------------
-- 5. create_payment_intent — a guardian or finance user starts a payment.

create or replace function public.create_payment_intent(
  p_learner_id uuid,
  p_amount     numeric,
  p_invoice_id uuid default null,
  p_return_url text default null,
  p_cancel_url text default null
) returns public.payment_intents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_config public.payment_gateway_configs;
  v_amount numeric(12, 2) := round(p_amount, 2);
  v_invoice record;
  v_allocated numeric(12, 2);
  v_reference text;
  v_result public.payment_intents;
begin
  select school_id into v_school_id from public.learners where id = p_learner_id;
  if not found then
    raise exception 'not_found: no learner %', p_learner_id;
  end if;

  if not (public.can_manage_learner_financial(v_school_id) or public.is_learner_guardian(p_learner_id)) then
    raise exception 'insufficient_privilege: not permitted to pay for this learner';
  end if;

  if v_amount <= 0 then
    raise exception 'invalid_argument: amount must be positive';
  end if;

  select * into v_config from public.payment_gateway_configs where school_id = v_school_id;
  if not found or not v_config.enabled then
    raise exception 'gateway_unavailable: this school has not enabled online payments';
  end if;

  if p_invoice_id is not null then
    select id, school_id, learner_id, status, total into v_invoice from public.invoices where id = p_invoice_id;
    if not found then
      raise exception 'not_found: no invoice %', p_invoice_id;
    end if;
    if v_invoice.school_id is distinct from v_school_id or v_invoice.learner_id is distinct from p_learner_id then
      raise exception 'insufficient_privilege: invoice does not belong to this learner';
    end if;
    if v_invoice.status <> 'issued' then
      raise exception 'invalid_state: can only pay an issued invoice';
    end if;
    select coalesce(sum(amount), 0) into v_allocated
      from public.learner_fee_payment_allocations where invoice_id = p_invoice_id;
    if v_amount > (v_invoice.total - v_allocated) then
      raise exception 'invalid_argument: amount exceeds the invoice outstanding balance';
    end if;
  end if;

  v_reference := 'PI-' || replace(gen_random_uuid()::text, '-', '');

  insert into public.payment_intents (
    school_id, learner_id, invoice_id, provider, mode, amount, reference, idempotency_key, return_url, cancel_url, created_by
  ) values (
    v_school_id, p_learner_id, p_invoice_id, v_config.provider, v_config.mode, v_amount, v_reference, v_reference, p_return_url, p_cancel_url, auth.uid()
  )
  returning * into v_result;

  perform public.write_audit_log(
    v_school_id, auth.uid(), 'payment_intent_created', 'payment_intents', v_result.id,
    null, jsonb_build_object('amount', v_amount, 'invoice_id', p_invoice_id, 'provider', v_config.provider)
  );

  return v_result;
end;
$$;

comment on function public.create_payment_intent(uuid, numeric, uuid, text, text) is
  'Starts an online payment for a learner (guardian or finance caller). Validates the school has an enabled gateway and, for an invoice payment, that the amount does not exceed the invoice outstanding balance. Returns a `created` intent whose `reference` the Edge Function hands the provider.';

revoke execute on function public.create_payment_intent(uuid, numeric, uuid, text, text) from public;
grant execute on function public.create_payment_intent(uuid, numeric, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. settle_payment_intent — the webhook handler's single entry point.
-- service_role ONLY. Idempotent, dedupe-safe, amount-checked.

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
  -- 1. Dedupe: first writer wins; a duplicate delivery is a silent no-op.
  insert into public.payment_webhook_events (provider, mode, provider_event_id, signature_valid, status_reported, payload)
  values (p_provider, p_mode, p_provider_event_id, p_signature_valid, p_outcome, p_payload)
  on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return jsonb_build_object('result', 'duplicate_ignored');
  end if;

  -- 2. Reject unverified signatures — recorded above, not acted on.
  if not p_signature_valid then
    update public.payment_webhook_events
      set processed_at = now(), processing_error = 'signature_invalid'
      where id = v_event_id;
    return jsonb_build_object('result', 'signature_invalid');
  end if;

  -- 3. Locate the intent.
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

  -- 4. Terminal already? Idempotent no-op.
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

  -- 5. Success — amount must match to the cent.
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

  -- 6. Book the payment into the same ledger every other payment uses.
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

  -- 7. Allocate to the invoice if there was one (cap at remaining balance).
  if v_intent.invoice_id is not null then
    select total into v_invoice from public.invoices where id = v_intent.invoice_id;
    select coalesce(sum(amount), 0) into v_allocated
      from public.learner_fee_payment_allocations where invoice_id = v_intent.invoice_id;
    v_alloc_amount := least(v_intent.amount, v_invoice.total - v_allocated);
    if v_alloc_amount > 0 then
      insert into public.learner_fee_payment_allocations (school_id, payment_id, invoice_id, amount)
      values (v_intent.school_id, v_payment_id, v_intent.invoice_id, v_alloc_amount);
    end if;
  end if;

  -- 8. Receipt. Created inline, not via issue_fee_receipt() — that RPC
  -- gates on can_manage_learner_financial(), which is false for the
  -- service_role session the webhook runs as (no JWT role).
  insert into public.fee_receipts (school_id, learner_id, payment_id, receipt_number, issued_by)
  values (v_intent.school_id, v_intent.learner_id, v_payment_id,
          public.next_fee_document_number(v_intent.school_id, 'receipt'), null);

  -- 9. Close the intent.
  update public.payment_intents
    set status = 'succeeded', payment_id = v_payment_id, provider_reference = p_provider_reference, raw_result = p_payload, completed_at = now()
    where id = v_intent.id;
  update public.payment_webhook_events set processed_at = now() where id = v_event_id;

  perform public.write_audit_log(
    v_intent.school_id, null, 'gateway_payment_settled', 'payment_intents', v_intent.id,
    null, jsonb_build_object('payment_id', v_payment_id, 'amount', v_intent.amount, 'provider', p_provider)
  );

  -- 10. Notify guardians.
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

comment on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) is
  'The webhook Edge Function''s only write path. service_role only. Idempotent (dedupes on provider_event_id and on an already-terminal intent), rejects signature_valid=false, requires an exact amount match, then books a card payment into learner_fee_payments, allocates it to the invoice, issues a receipt, and notifies guardians.';

revoke execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) from public;
revoke execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) from authenticated;
grant execute on function public.settle_payment_intent(public.payment_provider, public.payment_mode, text, text, text, numeric, text, boolean, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 7. mark_payment_intent_processing — the SPA calls this right before it
-- redirects the browser to the provider, so a stuck intent is
-- distinguishable from one never started. Client-callable but only for the
-- intent's own guardian/finance user, and only created -> processing.

create or replace function public.mark_payment_intent_processing(p_intent_id uuid)
returns public.payment_intents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intent public.payment_intents;
  v_result public.payment_intents;
begin
  select * into v_intent from public.payment_intents where id = p_intent_id;
  if not found then
    raise exception 'not_found: no payment intent %', p_intent_id;
  end if;
  if not (public.can_manage_learner_financial(v_intent.school_id) or public.is_learner_guardian(v_intent.learner_id)) then
    raise exception 'insufficient_privilege: not your payment intent';
  end if;
  if v_intent.status <> 'created' then
    return v_intent;
  end if;
  update public.payment_intents set status = 'processing' where id = p_intent_id returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.mark_payment_intent_processing(uuid) from public;
grant execute on function public.mark_payment_intent_processing(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. expire_stale_payment_intents — housekeeping. Safe to run from pg_cron
-- (not scheduled by this migration — the project has no cron entries in
-- git; the fee-overdue worker is likewise triggered manually + documented
-- as cron-ready).

create or replace function public.expire_stale_payment_intents()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with expired as (
    update public.payment_intents
      set status = 'expired', failure_reason = 'timeout', completed_at = now()
      where status in ('created', 'processing') and created_at < now() - interval '24 hours'
      returning 1
  )
  select count(*) into v_count from expired;
  return v_count;
end;
$$;

comment on function public.expire_stale_payment_intents() is
  'Marks created/processing intents older than 24h as expired. pg_cron-ready; not scheduled here (see fee-overdue worker precedent).';

revoke execute on function public.expire_stale_payment_intents() from public;
grant execute on function public.expire_stale_payment_intents() to service_role;
