-- Sebetsa Phase K — Tasks, Duties & Operational Workflows, migration 3 of 4.
--
-- Structured checklist items (relational, not an opaque JSON blob — per
-- the architecture principle that reporting/auditing needs querying, not
-- just display), evidence records (note-based only in this phase — file/
-- photo evidence is explicitly deferred to Phase M's document/storage
-- architecture, not fabricated here with an insecure ad-hoc upload path),
-- and reusable task templates (with minimal, safe recurrence — no
-- external scheduler; generate_recurring_tasks() is callable by a manager
-- or a future pg_cron job, same "cron-ready, not scheduled" posture Phase
-- H took with leave accrual).

create table public.task_checklist_items (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  task_id       uuid not null references public.tasks (id) on delete cascade,
  label         text not null check (char_length(label) > 0),
  sort_order    integer not null default 0,
  is_completed  boolean not null default false,
  completed_by  uuid references public.profiles (id) on delete set null,
  completed_at  timestamptz,
  notes         text,
  created_at    timestamptz not null default now()
);

comment on table public.task_checklist_items is 'Structured per-task checklist. completed_by/completed_at are server-derived (see toggle trigger below) — never client-supplied.';

create index task_checklist_items_tenant_id_idx on public.task_checklist_items (tenant_id);
create index task_checklist_items_task_id_idx on public.task_checklist_items (task_id, sort_order);

create or replace function public.validate_task_checklist_item_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.tasks where id = new.task_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: task % does not belong to tenant %', new.task_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger task_checklist_items_validate_tenant_ref
  before insert or update on public.task_checklist_items
  for each row
  execute function public.validate_task_checklist_item_tenant_ref();

-- completed_by/completed_at are server-derived the instant is_completed
-- flips true, and cleared if it flips back to false — never trusted from
-- the client even though the completion toggle itself is a direct,
-- RLS-gated table write (low-stakes, high-frequency, matching
-- employee_availability's "deliberately unaudited" precedent) rather
-- than a dedicated RPC.
create or replace function public.task_checklist_items_derive_completion()
returns trigger
language plpgsql
as $$
begin
  if new.is_completed and not old.is_completed then
    new.completed_by := auth.uid();
    new.completed_at := now();
  elsif not new.is_completed and old.is_completed then
    new.completed_by := null;
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create trigger task_checklist_items_derive_completion_trigger
  before update on public.task_checklist_items
  for each row
  execute function public.task_checklist_items_derive_completion();

alter table public.task_checklist_items enable row level security;
alter table public.task_checklist_items force row level security;

create policy task_checklist_items_select on public.task_checklist_items for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.tasks t join public.employees e on (e.id = t.assignee_id or e.id = t.supervisor_id)
      where t.id = task_checklist_items.task_id and e.profile_id = auth.uid()
    )
  );

-- Write: manager tier, or the task's own assignee (ticking off their own
-- checklist) — never anyone else's task.
create policy task_checklist_items_write on public.task_checklist_items for all to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.tasks t join public.employees e on e.id = t.assignee_id
      where t.id = task_checklist_items.task_id and e.profile_id = auth.uid()
    )
  )
  with check (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.tasks t join public.employees e on e.id = t.assignee_id
      where t.id = task_checklist_items.task_id and e.profile_id = auth.uid()
    )
  );

create trigger task_checklist_items_audit_log
  after insert or update on public.task_checklist_items
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- task_evidence: note-based only in Phase K. A future Phase M
-- document_id column will link real uploaded files once that secure
-- storage architecture exists — never bolted on ad hoc here.

create type public.task_evidence_kind as enum ('note', 'confirmation');

create table public.task_evidence (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  task_id       uuid not null references public.tasks (id) on delete cascade,
  kind          public.task_evidence_kind not null default 'note',
  note          text,
  submitted_by  uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  check (kind <> 'note' or (note is not null and char_length(note) > 0))
);

comment on table public.task_evidence is 'Evidence attached to a task. Note/confirmation only in Phase K — file/photo evidence is deferred to Phase M''s secure document/storage architecture, not an ad-hoc upload path here. submitted_by is server-derived.';

create index task_evidence_tenant_id_idx on public.task_evidence (tenant_id);
create index task_evidence_task_id_idx on public.task_evidence (task_id);

create or replace function public.validate_task_evidence_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.tasks where id = new.task_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: task % does not belong to tenant %', new.task_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger task_evidence_validate_tenant_ref
  before insert on public.task_evidence
  for each row
  execute function public.validate_task_evidence_tenant_ref();

alter table public.task_evidence enable row level security;
alter table public.task_evidence force row level security;

create policy task_evidence_select on public.task_evidence for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.tasks t join public.employees e on (e.id = t.assignee_id or e.id = t.supervisor_id)
      where t.id = task_evidence.task_id and e.profile_id = auth.uid()
    )
  );

-- Insert only (evidence is append-only — no UPDATE/DELETE policy, matching
-- the ledger/audit-log precedent for append-only records).
create policy task_evidence_insert on public.task_evidence for insert to authenticated
  with check (
    public.can_manage_operations(tenant_id)
    or exists (
      select 1 from public.tasks t join public.employees e on e.id = t.assignee_id
      where t.id = task_evidence.task_id and e.profile_id = auth.uid()
    )
  );

create trigger task_evidence_audit_log
  after insert on public.task_evidence
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- task_templates: reusable definitions + minimal safe recurrence.

create table public.task_templates (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  site_id               uuid not null references public.sites (id) on delete cascade,
  title                 text not null check (char_length(title) > 0),
  description           text,
  instructions          text,
  priority              public.task_priority not null default 'normal',
  expected_duration_minutes integer check (expected_duration_minutes is null or expected_duration_minutes > 0),
  requires_evidence     boolean not null default false,
  default_assignee_id   uuid references public.employees (id) on delete set null,
  default_team_id       uuid references public.teams (id) on delete set null,
  recurrence_frequency  text check (recurrence_frequency is null or recurrence_frequency in ('daily', 'weekly', 'monthly')),
  status                public.entity_status not null default 'active',
  last_generated_on     date,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.task_templates is 'Reusable task definition. recurrence_frequency + last_generated_on drive generate_recurring_tasks() (next migration) — at most one task instance is created per period, tracked by advancing last_generated_on, never a separate infinite-row recurrence log.';

create index task_templates_tenant_id_idx on public.task_templates (tenant_id);
create index task_templates_site_id_idx on public.task_templates (site_id);

create trigger task_templates_set_updated_at
  before update on public.task_templates
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_task_template_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.default_assignee_id is not null and not exists (select 1 from public.employees where id = new.default_assignee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.default_assignee_id, new.tenant_id;
  end if;
  if new.default_team_id is not null and not exists (select 1 from public.teams where id = new.default_team_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: team % does not belong to tenant %', new.default_team_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger task_templates_validate_tenant_refs
  before insert or update on public.task_templates
  for each row
  execute function public.validate_task_template_tenant_refs();

alter table public.task_templates enable row level security;
alter table public.task_templates force row level security;

create policy task_templates_select_within_tenant on public.task_templates for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy task_templates_write_by_manager on public.task_templates for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create trigger task_templates_audit_log
  after insert or update on public.task_templates
  for each row
  execute function public.audit_log_from_trigger();
