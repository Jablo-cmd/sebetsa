-- Sebetsa — P1 remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, High findings: compliance-record and
-- certification/qualification expiry sweeps are fully implemented
-- (sync_expired_compliance_records/sync_expired_qualifications) but never
-- actually invoked — a compliant record or a valid certification past its
-- expiry_date shows as valid indefinitely because nothing ever runs the
-- sweep. sync_expired_documents has the same shape but is at least
-- reachable on-demand from EmployeeDocumentsPage.tsx).
--
-- sync_expired_compliance_records(p_tenant_id)/sync_expired_qualifications
-- (p_tenant_id)/sync_expired_documents(p_tenant_id) are designed to be
-- called BY an authenticated privileged user for THEIR OWN tenant — each
-- checks can_manage_operations(p_tenant_id)/can_manage_employees(p_tenant_id)
-- against the caller's own auth.jwt(). A scheduled job has no such caller
-- context, so it cannot invoke these directly. Three new
-- sync_all_expired_*() wrapper functions loop across every organization
-- and perform the same UPDATE these per-tenant functions do, with no
-- per-caller permission check (there is no caller) — deliberately never
-- granted to authenticated/anon, so an ordinary user can never invoke the
-- "sweep every tenant" variant; only the scheduler (running with database-
-- owner privilege, not a request-scoped JWT) can reach them.

create or replace function public.sync_all_expired_compliance_records()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record record;
begin
  for v_record in
    update public.compliance_records
    set status = 'expired'
    where status not in ('expired', 'waived')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    if v_record.responsible_profile_id is not null then
      perform public.create_notification(
        v_record.responsible_profile_id, 'compliance_expired', 'Compliance record expired',
        'A compliance record you are responsible for has expired and needs renewal.',
        v_record.tenant_id, 'compliance_records', v_record.id, null
      );
    end if;

    perform public.write_audit_log(v_record.tenant_id, null, 'compliance_record_expired', 'compliance_records', v_record.id, null, jsonb_build_object('status', 'expired'));
  end loop;
end;
$$;

revoke execute on function public.sync_all_expired_compliance_records() from public, anon, authenticated;

comment on function public.sync_all_expired_compliance_records() is
  'System-wide compliance expiry sweep for the scheduled job — never granted to authenticated/anon. See sync_expired_compliance_records() for the per-tenant, permission-checked, user-invoked equivalent this mirrors.';

create or replace function public.sync_all_expired_qualifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  for v_row in
    update public.employee_qualifications
    set status = 'expired'
    where status not in ('expired', 'revoked')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    perform public.write_audit_log(v_row.tenant_id, null, 'employee_qualification_expired', 'employee_qualifications', v_row.id, null, jsonb_build_object('status', 'expired'));
  end loop;
end;
$$;

revoke execute on function public.sync_all_expired_qualifications() from public, anon, authenticated;

comment on function public.sync_all_expired_qualifications() is
  'System-wide qualification/certification expiry sweep for the scheduled job — never granted to authenticated/anon. See sync_expired_qualifications() for the per-tenant, permission-checked, user-invoked equivalent this mirrors.';

create or replace function public.sync_all_expired_documents()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.employee_documents
  set status = 'expired'
  where status = 'verified'
    and expiry_date is not null
    and expiry_date < current_date;
end;
$$;

revoke execute on function public.sync_all_expired_documents() from public, anon, authenticated;

comment on function public.sync_all_expired_documents() is
  'System-wide document expiry sweep for the scheduled job — never granted to authenticated/anon. See sync_expired_documents() for the per-tenant, permission-checked, user-invoked equivalent this mirrors.';

-- Scheduling: pg_cron is Supabase's standard managed mechanism for this
-- (enabled per-project under Database > Extensions on the hosted
-- platform) — no new Edge Function/deployment needed. Guarded so this
-- migration does not hard-fail in an environment where the extension
-- isn't installed (this repo's own local RLS-regression harness runs
-- against a bare postgres:16-alpine/native install with no pg_cron
-- available at all — the three functions above were verified directly by
-- calling them, independent of the scheduler; pg_cron's actual firing
-- must be confirmed against the real hosted project once deployed, per
-- docs/SEBETSA_REMEDIATION_REPORT.md).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    perform cron.unschedule(jobid) from cron.job where jobname = 'sebetsa_sync_expired_compliance_records';
    perform cron.schedule('sebetsa_sync_expired_compliance_records', '0 1 * * *', 'select public.sync_all_expired_compliance_records();');

    perform cron.unschedule(jobid) from cron.job where jobname = 'sebetsa_sync_expired_qualifications';
    perform cron.schedule('sebetsa_sync_expired_qualifications', '0 1 * * *', 'select public.sync_all_expired_qualifications();');

    perform cron.unschedule(jobid) from cron.job where jobname = 'sebetsa_sync_expired_documents';
    perform cron.schedule('sebetsa_sync_expired_documents', '0 1 * * *', 'select public.sync_all_expired_documents();');
  else
    raise notice 'pg_cron extension not available in this environment — sweep functions created, but not scheduled. Enable pg_cron under Database > Extensions on the hosted Supabase project and re-run the three cron.schedule(...) calls in this migration''s DO block.';
  end if;
end;
$$;
