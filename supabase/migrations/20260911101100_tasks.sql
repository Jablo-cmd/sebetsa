-- Sebetsa Phase 1 (remainder) — Tasks
-- Real operational work items at a site, distinct from scheduling (a task
-- is not itself a shift and doesn't imply attendance).

create type public.task_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.task_status as enum ('open', 'in_progress', 'completed', 'cancelled', 'escalated');

create table public.tasks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  site_id       uuid not null references public.sites (id) on delete cascade,
  assignee_id   uuid references public.employees (id) on delete set null,
  supervisor_id uuid references public.employees (id) on delete set null,
  title         text not null check (char_length(title) > 0),
  description   text,
  priority      public.task_priority not null default 'normal',
  status        public.task_status not null default 'open',
  due_at        timestamptz,
  completed_at  timestamptz,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index tasks_tenant_id_idx on public.tasks (tenant_id);
create index tasks_site_id_idx on public.tasks (site_id);
create index tasks_assignee_id_idx on public.tasks (assignee_id);
create index tasks_status_idx on public.tasks (status);
create index tasks_due_at_idx on public.tasks (due_at);

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row
  execute function public.set_updated_at();

create table public.task_comments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  task_id     uuid not null references public.tasks (id) on delete cascade,
  author_id   uuid references public.profiles (id) on delete set null,
  body        text not null check (char_length(body) > 0),
  created_at  timestamptz not null default now()
);

create index task_comments_tenant_id_idx on public.task_comments (tenant_id);
create index task_comments_task_id_idx on public.task_comments (task_id, created_at);

-- ---------------------------------------------------------------------------
alter table public.tasks enable row level security;
alter table public.tasks force row level security;
alter table public.task_comments enable row level security;
alter table public.task_comments force row level security;

create policy tasks_select_within_tenant on public.tasks for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy tasks_write_by_manager on public.tasks for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create policy task_comments_select_within_tenant on public.task_comments for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
-- Anyone who can see the tenant's tasks may comment (assignees included,
-- not only managers) — comments are lower-stakes than the task record
-- itself and every tenant member can already read tasks.
create policy task_comments_insert_within_tenant on public.task_comments for insert to authenticated
  with check (tenant_id = public.current_tenant_id());
