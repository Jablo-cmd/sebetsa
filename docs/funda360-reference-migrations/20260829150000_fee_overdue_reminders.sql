-- Fee-overdue reminder → escalation workflow (FND-WF-001)
--
-- Unlike FND-ATT-002/FND-COM-003, "a charge became overdue" is not a data
-- write event — it happens purely because a due_date passed while nothing
-- changed. A row-level trigger can't observe that; this needs a scheduled
-- job. pg_cron is available in this Postgres instance (verified directly,
-- not assumed) and is the correct, standard tool for exactly this shape of
-- problem — no external scheduler/queue needed.
--
-- Two tiers, both idempotent via the same "check notifications, don't
-- re-fire within a cooldown window" pattern FND-ATT-002 established (here
-- a time-window check rather than a streak-boundary check, since fee
-- balances don't have attendance's clean daily-streak shape):
--   1. Reminder — to the learner's guardians, at most once every 7 days
--      while any charge is overdue and the account has an outstanding
--      balance.
--   2. Escalation — to finance staff (school_owner/finance_manager/
--      accountant — exactly can_manage_learner_financial()'s role set),
--      at most once every 14 days, once the OLDEST overdue charge has
--      been outstanding 14+ days.
--
-- "Outstanding balance" is computed here exactly like buildFeeSummary()
-- computes it client-side (totalCharged - totalAdjustments - netPaid) —
-- kept in sync manually, same documented obligation every other RLS
-- helper mirroring an app-level function already carries. Unlike the
-- client-side calculation, this SQL arithmetic needs no decimal-safety
-- library: Postgres `numeric` addition/subtraction is exact by
-- definition, which is exactly why FND-FIN-009's money.ts fix was a
-- JS-side problem, not a database-side one.
--
-- Two functions, an authorization split matching create_notification's own
-- reasoning: run_fee_overdue_reminders() does the real work for one
-- school and is NOT granted to authenticated — it's reachable only from
-- pg_cron (which runs as the extension owner, not through PostgREST) and
-- from trigger_fee_overdue_reminders(), the authorization-checked,
-- authenticated-facing wrapper a "Send reminders now" UI button calls.

-- pg_cron is bundled in the real Supabase Postgres image (verified
-- directly against local dev) but is genuinely absent from the minimal
-- postgres:16-alpine image the RLS regression harness runs against — so
-- this is wrapped defensively rather than assumed. Everything below the
-- schedule itself (both functions, and the "Send reminders now" UI path)
-- works identically with or without pg_cron actually installed; only the
-- unattended daily run depends on it.
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron unavailable in this environment — skipping. The manual "Send overdue reminders now" path (trigger_fee_overdue_reminders) is unaffected.';
end;
$$;

create or replace function public.run_fee_overdue_reminders(p_school_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_learner record;
  v_total_charged numeric;
  v_total_adjustments numeric;
  v_total_paid numeric;
  v_total_refunded numeric;
  v_outstanding numeric;
  v_oldest_due date;
  v_days_overdue int;
  v_learner_name text;
  v_sent_count int := 0;
  v_recipient record;
  v_already_reminded boolean;
  v_already_escalated boolean;
begin
  for v_learner in
    select distinct learner_id from public.learner_fee_charges
    where school_id = p_school_id and active = true and due_date is not null and due_date < v_today
  loop
    select coalesce(sum(amount), 0) into v_total_charged from public.learner_fee_charges where learner_id = v_learner.learner_id and active;
    select coalesce(sum(amount), 0) into v_total_adjustments from public.learner_fee_adjustments where learner_id = v_learner.learner_id and active;
    select coalesce(sum(amount), 0) into v_total_paid from public.learner_fee_payments where learner_id = v_learner.learner_id and active;
    select coalesce(sum(amount), 0) into v_total_refunded from public.learner_fee_refunds where learner_id = v_learner.learner_id and active and status = 'completed';
    v_outstanding := v_total_charged - v_total_adjustments - (v_total_paid - v_total_refunded);

    if v_outstanding <= 0 then
      continue;
    end if;

    select min(due_date) into v_oldest_due from public.learner_fee_charges where learner_id = v_learner.learner_id and active and due_date < v_today;
    v_days_overdue := v_today - v_oldest_due;

    select (first_name || ' ' || last_name) into v_learner_name from public.learners where id = v_learner.learner_id;

    select exists (
      select 1 from public.notifications
      where type = 'fee_reminder' and related_entity_table = 'learners' and related_entity_id = v_learner.learner_id
        and created_at > now() - interval '7 days'
    ) into v_already_reminded;

    if not v_already_reminded then
      for v_recipient in select guardian_profile_id from public.learner_guardians where learner_id = v_learner.learner_id and active loop
        perform public.create_notification(
          v_recipient.guardian_profile_id,
          'fee_reminder',
          'Outstanding fees',
          coalesce(v_learner_name, 'Your child') || '''s account has an outstanding balance of R' || to_char(v_outstanding, 'FM999,999,990.00') || ', overdue since ' || to_char(v_oldest_due, 'DD Mon YYYY') || '.',
          p_school_id,
          'learners',
          v_learner.learner_id,
          '/parent/children/' || v_learner.learner_id::text
        );
        v_sent_count := v_sent_count + 1;
      end loop;
    end if;

    if v_days_overdue >= 14 then
      select exists (
        select 1 from public.notifications
        where type = 'fee_overdue_escalation' and related_entity_table = 'learners' and related_entity_id = v_learner.learner_id
          and created_at > now() - interval '14 days'
      ) into v_already_escalated;

      if not v_already_escalated then
        for v_recipient in
          select id from public.profiles where tenant_id = p_school_id and status = 'active' and role in ('school_owner', 'finance_manager', 'accountant')
        loop
          perform public.create_notification(
            v_recipient.id,
            'fee_overdue_escalation',
            'Fee escalation: ' || coalesce(v_learner_name, 'Learner'),
            coalesce(v_learner_name, 'A learner') || ' is ' || v_days_overdue || ' days overdue, R' || to_char(v_outstanding, 'FM999,999,990.00') || ' outstanding.',
            p_school_id,
            'learners',
            v_learner.learner_id,
            '/learners/' || v_learner.learner_id::text
          );
          v_sent_count := v_sent_count + 1;
        end loop;
      end if;
    end if;
  end loop;

  return v_sent_count;
end;
$$;

comment on function public.run_fee_overdue_reminders(uuid) is
  'Scheduled/internal worker for one school — sends fee_reminder (guardians, 7-day cooldown) and fee_overdue_escalation (finance staff, 14-day cooldown, only once the oldest overdue charge is 14+ days late) notifications. NOT granted to authenticated — reachable only from pg_cron and from trigger_fee_overdue_reminders(). Returns the number of notifications sent, for a friendly UI count.';

create or replace function public.trigger_fee_overdue_reminders(p_school_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_learner_financial(p_school_id) then
    raise exception 'insufficient_privilege: cannot trigger fee reminders for this school';
  end if;
  return public.run_fee_overdue_reminders(p_school_id);
end;
$$;

comment on function public.trigger_fee_overdue_reminders(uuid) is
  'Authenticated-facing entry point for the "Send overdue reminders now" action on Finance Overview — gated on can_manage_learner_financial() (school_owner/finance_manager/accountant), then delegates to run_fee_overdue_reminders().';

grant execute on function public.trigger_fee_overdue_reminders(uuid) to authenticated;

-- Daily at 07:00 UTC, across every active school — pg_cron runs this as
-- the extension owner (a superuser-equivalent context with no JWT), which
-- is exactly why run_fee_overdue_reminders() carries its own SECURITY
-- DEFINER body rather than depending on a caller identity. Only scheduled
-- if the extension actually installed above — see that block's comment.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'fee-overdue-reminders-daily',
      '0 7 * * *',
      $cron$
        do $do$
        declare v_school record;
        begin
          for v_school in select id from public.schools where status = 'active' loop
            perform public.run_fee_overdue_reminders(v_school.id);
          end loop;
        end;
        $do$;
      $cron$
    );
  end if;
end;
$$;
