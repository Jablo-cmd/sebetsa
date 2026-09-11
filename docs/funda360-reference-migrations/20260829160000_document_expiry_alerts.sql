-- Document-expiry alerting (FND-DOC-002, absorbs the former FND-WF-002)
--
-- learner_documents had no expiry concept at all — adds an optional
-- expiry_date (nullable: birth certificates etc. never expire; only
-- passports/permits/medical certificates typically do, and this schema
-- deliberately doesn't hard-code which document_type values qualify, the
-- same "open product-policy question" treatment already given to
-- category/gender elsewhere in this schema).
--
-- Same shape as FND-WF-001 (a scheduled job, not a trigger — "a document
-- is about to expire" is a passage-of-time event, not a data write) and
-- reuses its exact verified-working pg_cron infrastructure. Two tiers:
--   1. Expiring soon (0–30 days out) — reminds the learner's guardians,
--      14-day cooldown. They're the ones who'd actually renew a passport
--      or permit.
--   2. Expired — alerts staff who manage learner records
--      (can_manage_learners(): school_owner/principal/admissions_officer),
--      30-day cooldown. An expired required document on an enrolled
--      learner is a compliance concern staff need visibility into, not
--      something guardians alone are responsible for tracking.
--
-- No "send now" UI button was added for this one — unlike FND-WF-001,
-- there is no existing school-wide Documents page to put it on yet
-- (documents are shown per-learner only, on LearnerProfilePage's
-- Documents tab). trigger_document_expiry_alerts() is still built and
-- authorization-tested so it's ready the moment such a page exists;
-- documented here rather than silently omitted.

alter table public.learner_documents add column expiry_date date;

comment on column public.learner_documents.expiry_date is 'Optional — most document types (birth certificate, transfer letter, report card) never expire. Set only for documents that actually do (passport, permit, medical certificate, at staff discretion). Drives document_expiry alerts (FND-DOC-002).';

create or replace function public.run_document_expiry_alerts(p_school_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_doc record;
  v_learner_name text;
  v_sent_count int := 0;
  v_recipient record;
  v_already_notified boolean;
  v_doc_type_label text;
begin
  for v_doc in
    select id, learner_id, document_type, expiry_date
    from public.learner_documents
    where school_id = p_school_id and active = true and expiry_date is not null
      and (expiry_date >= v_today and expiry_date <= v_today + 30 or expiry_date < v_today)
  loop
    select (first_name || ' ' || last_name) into v_learner_name from public.learners where id = v_doc.learner_id;
    -- "medical_certificate" -> "Medical certificate" (first letter only —
    -- matches DOCUMENT_TYPE_LABELS' own capitalization convention in
    -- DocumentsTable.tsx, not initcap()'s every-word capitalization).
    v_doc_type_label := replace(v_doc.document_type::text, '_', ' ');
    v_doc_type_label := upper(left(v_doc_type_label, 1)) || substring(v_doc_type_label from 2);

    if v_doc.expiry_date < v_today then
      select exists (
        select 1 from public.notifications
        where type = 'document_expired' and related_entity_table = 'learner_documents' and related_entity_id = v_doc.id
          and created_at > now() - interval '30 days'
      ) into v_already_notified;

      if not v_already_notified then
        for v_recipient in
          select id from public.profiles where tenant_id = p_school_id and status = 'active' and role in ('school_owner', 'principal', 'admissions_officer')
        loop
          perform public.create_notification(
            v_recipient.id,
            'document_expired',
            'Document expired: ' || coalesce(v_learner_name, 'Learner'),
            v_doc_type_label || ' for ' || coalesce(v_learner_name, 'a learner') || ' expired on ' || to_char(v_doc.expiry_date, 'DD Mon YYYY') || '.',
            p_school_id,
            'learner_documents',
            v_doc.id,
            '/learners/' || v_doc.learner_id::text
          );
          v_sent_count := v_sent_count + 1;
        end loop;
      end if;
    else
      select exists (
        select 1 from public.notifications
        where type = 'document_expiring_soon' and related_entity_table = 'learner_documents' and related_entity_id = v_doc.id
          and created_at > now() - interval '14 days'
      ) into v_already_notified;

      if not v_already_notified then
        for v_recipient in select guardian_profile_id from public.learner_guardians where learner_id = v_doc.learner_id and active loop
          perform public.create_notification(
            v_recipient.guardian_profile_id,
            'document_expiring_soon',
            'Document expiring soon',
            coalesce(v_learner_name, 'Your child') || '''s ' || v_doc_type_label || ' expires on ' || to_char(v_doc.expiry_date, 'DD Mon YYYY') || '.',
            p_school_id,
            'learner_documents',
            v_doc.id,
            '/parent/children/' || v_doc.learner_id::text
          );
          v_sent_count := v_sent_count + 1;
        end loop;
      end if;
    end if;
  end loop;

  return v_sent_count;
end;
$$;

comment on function public.run_document_expiry_alerts(uuid) is
  'Scheduled/internal worker for one school — document_expiring_soon (guardians, 0-30 days out, 14-day cooldown) and document_expired (school_owner/principal/admissions_officer, 30-day cooldown). NOT granted to authenticated — reachable only from pg_cron and trigger_document_expiry_alerts(). Same idempotency-via-notifications-window pattern as run_fee_overdue_reminders().';

create or replace function public.trigger_document_expiry_alerts(p_school_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_learners(p_school_id) then
    raise exception 'insufficient_privilege: cannot trigger document expiry alerts for this school';
  end if;
  return public.run_document_expiry_alerts(p_school_id);
end;
$$;

comment on function public.trigger_document_expiry_alerts(uuid) is
  'Authenticated-facing entry point, gated on can_manage_learners(). No UI caller exists yet (no school-wide Documents page) — built and tested so it is ready the moment one does.';

grant execute on function public.trigger_document_expiry_alerts(uuid) to authenticated;

-- Daily at 07:15 UTC (offset from the 07:00 fee-reminder job so they don't
-- contend), across every active school. Same graceful-skip-if-pg_cron-
-- unavailable wrapping as FND-WF-001 — see that migration's comment for
-- why (the RLS regression harness's minimal postgres image has no
-- pg_cron installed; the real Supabase stack does, verified directly).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'document-expiry-alerts-daily',
      '15 7 * * *',
      $cron$
        do $do$
        declare v_school record;
        begin
          for v_school in select id from public.schools where status = 'active' loop
            perform public.run_document_expiry_alerts(v_school.id);
          end loop;
        end;
        $do$;
      $cron$
    );
  end if;
end;
$$;
