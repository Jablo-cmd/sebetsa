-- Sebetsa Phase I — Attendance & Time Management
--
-- Extends the existing attendance_records (Phase 1) rather than creating a
-- parallel table. Adds: break tracking, policy-driven late/early-departure/
-- overtime computation (stored + trigger-maintained for indexable
-- filtering, never trusted from the client), a controlled correction
-- workflow (request -> approve/reject, never a silent historical mutation),
-- and leave integration (approved leave marks/keeps an existing attendance
-- row 'excused' rather than 'absent' — never force-creates one, matching
-- the Phase H architecture's own "attendance is a separate fact, never
-- manufactured" rule).
--
-- Additive only — no historical migration touched.

-- ---------------------------------------------------------------------------
-- attendance_policies: tenant-level grace/threshold configuration. Not
-- hard-coded — a tenant with no row falls back to sensible defaults (see
-- compute_attendance_metrics below) rather than failing.

create table public.attendance_policies (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.organizations (id) on delete cascade unique,
  grace_period_minutes        integer not null default 5 check (grace_period_minutes >= 0),
  early_departure_threshold_minutes integer not null default 5 check (early_departure_threshold_minutes >= 0),
  overtime_threshold_minutes  integer not null default 15 check (overtime_threshold_minutes >= 0),
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

comment on table public.attendance_policies is
  'One configurable row per tenant. A tenant with no row uses the hard-coded fallback defaults in compute_attendance_metrics() (5/5/15 minutes) — not a separate code path, the same defaults this table itself ships with.';

create trigger attendance_policies_set_updated_at
  before update on public.attendance_policies
  for each row
  execute function public.set_updated_at();

alter table public.attendance_policies enable row level security;
alter table public.attendance_policies force row level security;

create policy attendance_policies_select_within_tenant on public.attendance_policies for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy attendance_policies_write_by_manager on public.attendance_policies for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create trigger attendance_policies_audit_log
  after insert or update on public.attendance_policies
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- attendance_records: extend with break-adjacent worked-time metrics.
-- Computed server-side only (see compute trigger below) — never trusted
-- from the client, per architecture principle "prefer database
-- constraints... over frontend assumptions."

alter table public.attendance_records add column late_minutes integer;
alter table public.attendance_records add column early_departure_minutes integer;
alter table public.attendance_records add column worked_minutes integer;
alter table public.attendance_records add column overtime_minutes integer;

create index attendance_records_status_idx on public.attendance_records (status);

comment on column public.attendance_records.late_minutes is 'Minutes clocked in after (shift start + policy grace period). Null if not late or no shift. Server-computed by attendance_records_compute_metrics_trigger — never client-supplied.';
comment on column public.attendance_records.worked_minutes is 'clock_out_at - clock_in_at, minus total break duration. Null until clocked out.';

-- ---------------------------------------------------------------------------
-- attendance_breaks: one row per break. A break without an end is "in
-- progress" — mirrors attendance_records.clock_out_at being nullable for
-- the same reason.

create table public.attendance_breaks (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  attendance_record_id  uuid not null references public.attendance_records (id) on delete cascade,
  break_start           timestamptz not null default now(),
  break_end             timestamptz,
  created_at            timestamptz not null default now(),
  check (break_end is null or break_end >= break_start)
);

comment on table public.attendance_breaks is 'One row per break within one attendance_record. A row with break_end=null is the currently open break — start_break()/end_break() enforce at most one open break per attendance record.';

create index attendance_breaks_tenant_id_idx on public.attendance_breaks (tenant_id);
create index attendance_breaks_attendance_record_id_idx on public.attendance_breaks (attendance_record_id);

-- At most one open (break_end is null) break per attendance record —
-- database-enforced, not just RPC-checked, closing the same "impossible
-- sequence" gap the brief calls out for clock events generally.
create unique index attendance_breaks_one_open_per_record_idx
  on public.attendance_breaks (attendance_record_id)
  where (break_end is null);

create or replace function public.validate_attendance_break_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.attendance_records where id = new.attendance_record_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: attendance record % does not belong to tenant %', new.attendance_record_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger attendance_breaks_validate_tenant_ref
  before insert or update on public.attendance_breaks
  for each row
  execute function public.validate_attendance_break_tenant_ref();

alter table public.attendance_breaks enable row level security;
alter table public.attendance_breaks force row level security;

-- Read follows the same rule as attendance_records itself (see hardening
-- below): tenant-wide operational tier, or the employee's own record.
create policy attendance_breaks_select on public.attendance_breaks for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.attendance_records ar
      join public.employees e on e.id = ar.employee_id
      where ar.id = attendance_breaks.attendance_record_id and e.profile_id = auth.uid()
    )
  );

-- No direct client write policy — start_break()/end_break() (RPCs below)
-- are the only path, matching the leave_balance_transactions ledger
-- pattern: no INSERT/UPDATE policy for `authenticated` at all.

create trigger attendance_breaks_audit_log
  after insert or update on public.attendance_breaks
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- attendance_corrections: controlled correction workflow. Every correction
-- is requested, then approved/rejected — never a silent UPDATE of
-- attendance_records' authoritative fields (enforced by revoking direct
-- client UPDATE on the fields that matter — see hardening below).

create type public.attendance_correction_field as enum ('clock_in_at', 'clock_out_at', 'status');
create type public.attendance_correction_status as enum ('pending', 'approved', 'rejected');

create table public.attendance_corrections (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  attendance_record_id  uuid not null references public.attendance_records (id) on delete cascade,
  field                 public.attendance_correction_field not null,
  previous_value        text,
  new_value             text not null,
  reason                text not null check (char_length(reason) > 0),
  status                public.attendance_correction_status not null default 'pending',
  requested_by          uuid references public.profiles (id) on delete set null,
  reviewed_by           uuid references public.profiles (id) on delete set null,
  reviewed_at           timestamptz,
  review_notes          text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.attendance_corrections is 'A requested change to one field of one attendance_record. requested_by/reviewed_by/reviewed_at are server-derived (see request_attendance_correction/decide_attendance_correction RPCs) — never client-supplied. Approving applies the change to attendance_records; rejecting does not.';

create index attendance_corrections_tenant_id_idx on public.attendance_corrections (tenant_id);
create index attendance_corrections_attendance_record_id_idx on public.attendance_corrections (attendance_record_id);
create index attendance_corrections_status_idx on public.attendance_corrections (status);

create trigger attendance_corrections_set_updated_at
  before update on public.attendance_corrections
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_attendance_correction_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.attendance_records where id = new.attendance_record_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: attendance record % does not belong to tenant %', new.attendance_record_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger attendance_corrections_validate_tenant_ref
  before insert or update on public.attendance_corrections
  for each row
  execute function public.validate_attendance_correction_tenant_ref();

alter table public.attendance_corrections enable row level security;
alter table public.attendance_corrections force row level security;

create policy attendance_corrections_select on public.attendance_corrections for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.attendance_records ar
      join public.employees e on e.id = ar.employee_id
      where ar.id = attendance_corrections.attendance_record_id and e.profile_id = auth.uid()
    )
  );

-- No direct client INSERT/UPDATE policy — request_attendance_correction()/
-- decide_attendance_correction() (RPCs below) are the only path, so
-- status/reviewed_by/reviewed_at can never be forged by a direct write.

create trigger attendance_corrections_audit_log
  after insert or update on public.attendance_corrections
  for each row
  execute function public.audit_log_from_trigger();
