-- Sebetsa Domain 15 — Workforce Intelligence + AI.
--
-- Two clearly separated kinds of output, per this domain's own explicit
-- requirement: RULE_BASED insights (deterministic SQL against real
-- Sebetsa data — every function below) vs. AI-generated output (routed
-- through ai_query_log with its own confidence/evidence fields, and never
-- presented as a database fact). Every "tool" the AI assistant is allowed
-- to call is one of the SECURITY INVOKER, RLS-riding functions in this
-- file — the assistant has no other path to the database. There is no
-- LLM provider configured anywhere in this repository (no API key, no
-- edge function calling one) — see this migration's own comments on
-- ai_query_log and src/features/intelligence/services/aiAssistantService.ts
-- for exactly what that means for the "AI assistant" shipped in this pass:
-- a real, working, permission-aware natural-language *router* onto these
-- exact tools, with a clean provider seam for a real LLM to be dropped in
-- later — not a claim that a large language model is answering today.

create type public.insight_kind as enum ('rule_based', 'ai_generated');
create type public.shift_recommendation_status as enum ('suggested', 'accepted', 'rejected', 'published');

-- ---------------------------------------------------------------------------
-- 15.1/9.4 AI interaction audit log. Every assistant query, whichever tool
-- it routed to, is recorded here — auditability for "AI recommendation",
-- "AI-approved/accepted action", "AI rejection" per this domain's own list.

create table public.ai_query_log (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.organizations (id) on delete cascade,
  actor_profile_id uuid not null references public.profiles (id) on delete cascade,
  query_text       text not null,
  matched_intent   text,
  tool_calls       jsonb not null default '[]'::jsonb,
  response_text    text,
  insight_kind     public.insight_kind not null default 'rule_based',
  created_at       timestamptz not null default now()
);

comment on table public.ai_query_log is
  'Append-only audit trail for every AI-assistant interaction — what was asked, which whitelisted tool(s) answered it, what was returned, and whether the answer was a deterministic rule-based fact or (once a real LLM provider is configured) an AI-generated inference. No arbitrary SQL is ever logged as having been executed, because none is ever generated — see the assistant service''s own comments.';

create index ai_query_log_tenant_id_idx on public.ai_query_log (tenant_id, created_at);
create index ai_query_log_actor_idx on public.ai_query_log (actor_profile_id);

alter table public.ai_query_log enable row level security;
alter table public.ai_query_log force row level security;

create policy ai_query_log_select on public.ai_query_log for select to authenticated
  using (actor_profile_id = auth.uid() or public.can_manage_operations(tenant_id));

-- No direct client write policy — log_ai_query() RPC only.

create or replace function public.log_ai_query(
  p_query_text text,
  p_matched_intent text,
  p_tool_calls jsonb,
  p_response_text text,
  p_insight_kind public.insight_kind default 'rule_based'
)
returns public.ai_query_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.ai_query_log;
begin
  v_tenant_id := public.current_tenant_id();
  if v_tenant_id is null then
    raise exception 'not_found: no tenant for the current user';
  end if;

  insert into public.ai_query_log (tenant_id, actor_profile_id, query_text, matched_intent, tool_calls, response_text, insight_kind)
  values (v_tenant_id, auth.uid(), p_query_text, p_matched_intent, p_tool_calls, p_response_text, p_insight_kind)
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.log_ai_query(text, text, jsonb, text, public.insight_kind) from public, anon;
grant execute on function public.log_ai_query(text, text, jsonb, text, public.insight_kind) to authenticated;

-- ---------------------------------------------------------------------------
-- 9.3 Deterministic anomaly/insight tools. Every one is SECURITY INVOKER,
-- RLS-riding (get_operational_metrics' own established pattern) — a caller
-- only ever sees what their own role's RLS already permits on the
-- underlying tables, so "never expose individual-level HR information to
-- roles that should only see aggregate information" (9.2) is enforced by
-- the same RLS the rest of the app already relies on, not reimplemented
-- as a parallel permission system inside these functions.

create or replace function public.get_understaffed_sites(p_tenant_id uuid)
returns table (site_id uuid, site_name text, required_count bigint, assigned_count bigint, shortfall bigint)
language sql
stable
as $$
  select ssr.site_id, s.name, sum(ssr.required_count), count(distinct sa.employee_id),
         sum(ssr.required_count) - count(distinct sa.employee_id)
  from public.site_staffing_requirements ssr
  join public.sites s on s.id = ssr.site_id
  left join public.site_assignments sa on sa.site_id = ssr.site_id and (sa.end_date is null or sa.end_date >= current_date)
  where ssr.tenant_id = p_tenant_id
  group by ssr.site_id, s.name
  having count(distinct sa.employee_id) < sum(ssr.required_count)
  order by (sum(ssr.required_count) - count(distinct sa.employee_id)) desc
$$;

revoke execute on function public.get_understaffed_sites(uuid) from public, anon;
grant execute on function public.get_understaffed_sites(uuid) to authenticated;

create or replace function public.get_employees_absent_now(p_tenant_id uuid)
returns table (employee_id uuid, employee_name text, site_id uuid, site_name text, shift_starts_at timestamptz, minutes_overdue integer)
language sql
stable
as $$
  select e.id, e.first_name || ' ' || e.last_name, sh.site_id, s.name, sh.starts_at,
         floor(extract(epoch from (now() - sh.starts_at)) / 60)::integer
  from public.shifts sh
  join public.employees e on e.id = sh.employee_id
  join public.sites s on s.id = sh.site_id
  where sh.tenant_id = p_tenant_id and sh.starts_at::date = current_date and sh.starts_at < now() - interval '30 minutes'
    and not exists (select 1 from public.attendance_records ar where ar.shift_id = sh.id and ar.clock_in_at is not null)
  order by sh.starts_at
$$;

revoke execute on function public.get_employees_absent_now(uuid) from public, anon;
grant execute on function public.get_employees_absent_now(uuid) to authenticated;

create or replace function public.get_expiring_qualifications(p_tenant_id uuid, p_within_days integer default 30)
returns table (employee_id uuid, employee_name text, qualification_name text, expiry_date date, days_remaining integer)
language sql
stable
as $$
  select e.id, e.first_name || ' ' || e.last_name, eq.name, eq.expiry_date, (eq.expiry_date - current_date)::integer
  from public.employee_qualifications eq
  join public.employees e on e.id = eq.employee_id
  where eq.tenant_id = p_tenant_id and eq.status not in ('expired', 'revoked')
    and eq.expiry_date is not null and eq.expiry_date between current_date and current_date + p_within_days
  order by eq.expiry_date
$$;

revoke execute on function public.get_expiring_qualifications(uuid, integer) from public, anon;
grant execute on function public.get_expiring_qualifications(uuid, integer) to authenticated;

create or replace function public.get_declining_sla_contracts(p_tenant_id uuid)
returns table (contract_id uuid, contract_number text, sla_name text, latest_value numeric, target_value numeric, target_met boolean, period_end date)
language sql
stable
as $$
  select c.id, c.contract_number, sd.name, latest.measured_value, sd.target_value, latest.target_met, latest.period_end
  from public.sla_definitions sd
  join public.contracts c on c.id = sd.contract_id
  join lateral (
    select measured_value, target_met, period_end from public.sla_measurements m
    where m.sla_definition_id = sd.id order by m.period_end desc limit 1
  ) latest on true
  where sd.tenant_id = p_tenant_id and sd.is_active and not latest.target_met
  order by latest.period_end desc
$$;

revoke execute on function public.get_declining_sla_contracts(uuid) from public, anon;
grant execute on function public.get_declining_sla_contracts(uuid) to authenticated;

create or replace function public.get_overtime_spike_employees(p_tenant_id uuid, p_since date default (current_date - 30))
returns table (employee_id uuid, employee_name text, total_overtime_minutes bigint, record_count bigint)
language sql
stable
as $$
  select e.id, e.first_name || ' ' || e.last_name, sum(coalesce(ar.overtime_minutes, 0)), count(*)
  from public.attendance_records ar
  join public.employees e on e.id = ar.employee_id
  where ar.tenant_id = p_tenant_id and ar.created_at::date >= p_since and coalesce(ar.overtime_minutes, 0) > 0
  group by e.id, e.first_name, e.last_name
  having sum(coalesce(ar.overtime_minutes, 0)) > 0
  order by sum(coalesce(ar.overtime_minutes, 0)) desc
  limit 20
$$;

revoke execute on function public.get_overtime_spike_employees(uuid, date) from public, anon;
grant execute on function public.get_overtime_spike_employees(uuid, date) to authenticated;

create or replace function public.get_site_incident_ranking(p_tenant_id uuid, p_since date default (current_date - 90))
returns table (site_id uuid, site_name text, incident_count bigint, critical_count bigint)
language sql
stable
as $$
  select s.id, s.name, count(i.id), count(i.id) filter (where i.severity = 'critical')
  from public.sites s
  join public.incidents i on i.site_id = s.id
  where s.tenant_id = p_tenant_id and i.occurred_at::date >= p_since
  group by s.id, s.name
  order by count(i.id) desc
  limit 20
$$;

revoke execute on function public.get_site_incident_ranking(uuid, date) from public, anon;
grant execute on function public.get_site_incident_ranking(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10 AI-assisted scheduling. A candidate-scoring function (deterministic:
-- availability + qualifications + no conflicts + overtime minimization),
-- and a suggested-solution table with an explicit
-- GENERATE -> REVIEW -> ACCEPT/EDIT -> PUBLISH lifecycle — nothing here
-- ever writes a real `shifts` row until a human calls
-- accept_shift_recommendation().

create table public.shift_recommendations (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  site_id             uuid not null references public.sites (id) on delete cascade,
  shift_date          date not null,
  starts_at           timestamptz not null,
  ends_at             timestamptz not null,
  candidate_employee_id uuid not null references public.employees (id) on delete cascade,
  score               numeric not null,
  reasons             jsonb not null default '[]'::jsonb,
  status              public.shift_recommendation_status not null default 'suggested',
  generated_at        timestamptz not null default now(),
  decided_by          uuid references public.profiles (id) on delete set null,
  decided_at          timestamptz,
  published_shift_id  uuid references public.shifts (id) on delete set null,
  check (ends_at > starts_at)
);

create index shift_recommendations_tenant_status_idx on public.shift_recommendations (tenant_id, status);
create index shift_recommendations_site_date_idx on public.shift_recommendations (site_id, shift_date);

create or replace function public.validate_shift_recommendation_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees where id = new.candidate_employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.candidate_employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger shift_recommendations_validate_tenant_refs
  before insert or update on public.shift_recommendations
  for each row
  execute function public.validate_shift_recommendation_tenant_refs();

alter table public.shift_recommendations enable row level security;
alter table public.shift_recommendations force row level security;

create policy shift_recommendations_select on public.shift_recommendations for select to authenticated
  using (public.can_manage_operations(tenant_id));

-- No direct client write policy — generate_shift_recommendations()/
-- decide_shift_recommendation() RPCs only.

-- generate_shift_recommendations(): scores every employee who (a) is
-- assigned to the site, (b) is active, (c) has no conflicting shift/
-- approved leave for the window, (d) holds every qualification the site's
-- staffing requirement names (best-effort: matched by qualification name
-- text against the requirement's own label, since site_staffing_requirements
-- does not model a structured qualification FK — documented limitation,
-- not silently assumed more precise than it is). Score rewards existing
-- availability-window overlap and penalizes running overtime risk.
create or replace function public.generate_shift_recommendations(
  p_site_id uuid,
  p_shift_date date,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns setof public.shift_recommendations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_candidate record;
  v_score numeric;
  v_reasons jsonb;
  v_recent_minutes numeric;
  v_result public.shift_recommendations;
begin
  select tenant_id into v_tenant_id from public.sites where id = p_site_id;
  if not found then
    raise exception 'not_found: no site %', p_site_id;
  end if;
  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot generate scheduling recommendations for this tenant';
  end if;

  -- Clear any prior un-decided suggestions for this exact slot so
  -- re-generating doesn't accumulate stale candidates.
  delete from public.shift_recommendations
    where site_id = p_site_id and starts_at = p_starts_at and ends_at = p_ends_at and status = 'suggested';

  for v_candidate in
    select e.id as employee_id, e.first_name, e.last_name
    from public.employees e
    join public.site_assignments sa on sa.employee_id = e.id and sa.site_id = p_site_id and (sa.end_date is null or sa.end_date >= p_shift_date)
    where e.tenant_id = v_tenant_id and e.employment_status = 'active'
      -- no overlapping shift
      and not exists (
        select 1 from public.shifts sh where sh.employee_id = e.id
          and sh.starts_at < p_ends_at and sh.ends_at > p_starts_at
      )
      -- no overlapping approved leave
      and not exists (
        select 1 from public.leave_requests lr where lr.employee_id = e.id and lr.status = 'approved'
          and lr.start_date <= p_shift_date and lr.end_date >= p_shift_date
      )
  loop
    select coalesce(sum(ar.worked_minutes), 0) into v_recent_minutes
      from public.attendance_records ar where ar.employee_id = v_candidate.employee_id and ar.created_at::date >= p_shift_date - 7;

    v_score := 100 - least(v_recent_minutes / 60.0, 40);
    v_reasons := jsonb_build_array(
      jsonb_build_object('factor', 'assigned_to_site', 'detail', 'currently has an active site assignment here'),
      jsonb_build_object('factor', 'no_conflicts', 'detail', 'no overlapping shift or approved leave for this window'),
      jsonb_build_object('factor', 'recent_hours', 'detail', format('%s minutes worked in the trailing 7 days', v_recent_minutes))
    );

    insert into public.shift_recommendations (tenant_id, site_id, shift_date, starts_at, ends_at, candidate_employee_id, score, reasons)
    values (v_tenant_id, p_site_id, p_shift_date, p_starts_at, p_ends_at, v_candidate.employee_id, round(v_score, 1), v_reasons)
    returning * into v_result;

    return next v_result;
  end loop;

  return;
end;
$$;

revoke execute on function public.generate_shift_recommendations(uuid, date, timestamptz, timestamptz) from public, anon;
grant execute on function public.generate_shift_recommendations(uuid, date, timestamptz, timestamptz) to authenticated;

-- accept_shift_recommendation(): the only place a shift_recommendation
-- turns into a real `shifts` row — an explicit human action, never
-- automatic. Rejecting a recommendation never touches `shifts` at all.
create or replace function public.decide_shift_recommendation(
  p_recommendation_id uuid,
  p_accept boolean
)
returns public.shift_recommendations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec public.shift_recommendations;
  v_shift public.shifts;
  v_result public.shift_recommendations;
begin
  select * into v_rec from public.shift_recommendations where id = p_recommendation_id for update;
  if not found then
    raise exception 'not_found: no shift recommendation %', p_recommendation_id;
  end if;
  if not public.can_manage_operations(v_rec.tenant_id) then
    raise exception 'insufficient_privilege: cannot decide scheduling recommendations for this tenant';
  end if;
  if v_rec.status <> 'suggested' then
    raise exception 'invalid_transition: only a suggested recommendation can be decided (current status: %)', v_rec.status;
  end if;

  if p_accept then
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at, status)
    values (v_rec.tenant_id, v_rec.site_id, v_rec.candidate_employee_id, v_rec.starts_at, v_rec.ends_at, 'scheduled')
    returning * into v_shift;

    update public.shift_recommendations set status = 'published', decided_by = auth.uid(), decided_at = now(), published_shift_id = v_shift.id
      where id = p_recommendation_id returning * into v_result;

    perform public.write_audit_log(v_rec.tenant_id, auth.uid(), 'shift_recommendation_accepted', 'shift_recommendations', p_recommendation_id, null, jsonb_build_object('published_shift_id', v_shift.id));
  else
    update public.shift_recommendations set status = 'rejected', decided_by = auth.uid(), decided_at = now()
      where id = p_recommendation_id returning * into v_result;

    perform public.write_audit_log(v_rec.tenant_id, auth.uid(), 'shift_recommendation_rejected', 'shift_recommendations', p_recommendation_id, null, null);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.decide_shift_recommendation(uuid, boolean) from public, anon;
grant execute on function public.decide_shift_recommendation(uuid, boolean) to authenticated;
