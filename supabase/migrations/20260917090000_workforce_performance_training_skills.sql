-- Sebetsa Phase Q — Workforce Performance, Training & Skills, migration 1 of 2.
--
-- Four coordinated sub-domains, integrated with existing employees/
-- documents/RBAC rather than duplicating them:
--   1. Skills: a tenant-defined catalogue + structured per-employee
--      proficiency (never free-text, so it can be reported on).
--   2. Qualifications/certifications: expiry-tracked, verified, evidence
--      linked to Phase M's employee_documents rather than a second upload
--      mechanism.
--   3. Training: programmes + tenant-configurable requirements (by role or
--      site — never hard-coded) + employee enrolment/completion.
--   4. Performance: a review workflow with a finalisation lock and a
--      permanent development-actions list.
--
-- Privacy (Q.9): performance/training/qualification data is HR-sensitive.
-- Visibility follows can_manage_employees() (Phase C: organization_
-- administrator/operations_manager/hr_user) plus the employee's own
-- record — the SAME narrower tier employee_documents already uses, NOT
-- the broader can_manage_operations() tier (site_manager/supervisor/
-- regional_manager see none of this by default; it is an HR domain, not
-- an operational one, mirroring Phase M's own reasoning exactly).

create type public.proficiency_level as enum ('beginner', 'intermediate', 'advanced', 'expert');
create type public.credential_type as enum ('qualification', 'certification');
create type public.credential_status as enum ('pending_verification', 'verified', 'expired', 'revoked');
create type public.training_enrollment_status as enum ('scheduled', 'in_progress', 'completed', 'failed', 'cancelled');
create type public.performance_review_status as enum ('draft', 'manager_review', 'employee_review', 'acknowledgement', 'finalized');

-- ---------------------------------------------------------------------------
-- Skills catalogue + per-employee proficiency.

create table public.skills (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  category    text not null check (char_length(category) > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index skills_tenant_id_idx on public.skills (tenant_id);

create trigger skills_set_updated_at
  before update on public.skills
  for each row
  execute function public.set_updated_at();

alter table public.skills enable row level security;
alter table public.skills force row level security;

create policy skills_select on public.skills for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy skills_write on public.skills for all to authenticated
  using (public.can_manage_employees(tenant_id))
  with check (public.can_manage_employees(tenant_id));

create table public.employee_skills (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  employee_id       uuid not null references public.employees (id) on delete cascade,
  skill_id          uuid not null references public.skills (id) on delete cascade,
  proficiency_level public.proficiency_level not null default 'beginner',
  evidence_document_id uuid references public.employee_documents (id) on delete set null,
  verified_by       uuid references public.profiles (id) on delete set null,
  verified_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (employee_id, skill_id)
);

comment on table public.employee_skills is
  'verified_by/verified_at are server-derived (verify_employee_skill() RPC only).';

create index employee_skills_tenant_id_idx on public.employee_skills (tenant_id);
create index employee_skills_employee_id_idx on public.employee_skills (employee_id);

create trigger employee_skills_set_updated_at
  before update on public.employee_skills
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_employee_skill_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.skills s where s.id = new.skill_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: skill % does not belong to tenant %', new.skill_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger employee_skills_validate_tenant_refs
  before insert or update on public.employee_skills
  for each row
  execute function public.validate_employee_skill_tenant_refs();

alter table public.employee_skills enable row level security;
alter table public.employee_skills force row level security;

create policy employee_skills_select on public.employee_skills for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = employee_skills.employee_id and e.profile_id = auth.uid())
    or public.can_manage_employees(tenant_id)
  );

create policy employee_skills_write on public.employee_skills for all to authenticated
  using (public.can_manage_employees(tenant_id))
  with check (public.can_manage_employees(tenant_id));

create trigger employee_skills_audit_log
  after insert or update on public.employee_skills
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Qualifications & certifications — evidence lives in Phase M's
-- employee_documents, never a second upload path.

create table public.employee_qualifications (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  employee_id           uuid not null references public.employees (id) on delete cascade,
  credential_type       public.credential_type not null,
  name                  text not null check (char_length(name) > 0),
  issuing_organization  text,
  issue_date            date,
  expiry_date           date,
  status                public.credential_status not null default 'pending_verification',
  evidence_document_id  uuid references public.employee_documents (id) on delete set null,
  verified_by           uuid references public.profiles (id) on delete set null,
  verified_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.employee_qualifications is
  'status/verified_by/verified_at are server-derived (verify_employee_qualification()/sync_expired_qualifications() RPCs only).';

create index employee_qualifications_tenant_id_idx on public.employee_qualifications (tenant_id);
create index employee_qualifications_employee_id_idx on public.employee_qualifications (employee_id);
create index employee_qualifications_expiry_date_idx on public.employee_qualifications (expiry_date);

create trigger employee_qualifications_set_updated_at
  before update on public.employee_qualifications
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_employee_qualification_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  if new.evidence_document_id is not null and not exists (
    select 1 from public.employee_documents d where d.id = new.evidence_document_id and d.employee_id = new.employee_id
  ) then
    raise exception 'cross_reference: evidence document % does not belong to employee %', new.evidence_document_id, new.employee_id;
  end if;
  return new;
end;
$$;

create trigger employee_qualifications_validate_tenant_refs
  before insert or update on public.employee_qualifications
  for each row
  execute function public.validate_employee_qualification_tenant_refs();

alter table public.employee_qualifications enable row level security;
alter table public.employee_qualifications force row level security;

create policy employee_qualifications_select on public.employee_qualifications for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = employee_qualifications.employee_id and e.profile_id = auth.uid())
    or public.can_manage_employees(tenant_id)
  );

-- No direct client write — upsert_employee_qualification()/verify_
-- employee_qualification() RPCs only (verification must be server-derived).

create trigger employee_qualifications_audit_log
  after insert or update on public.employee_qualifications
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Training: programmes, tenant-configurable requirements, enrolments.

create table public.training_programs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  name          text not null check (char_length(name) > 0),
  description   text,
  category      text not null check (char_length(category) > 0),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, name)
);

create index training_programs_tenant_id_idx on public.training_programs (tenant_id);

create trigger training_programs_set_updated_at
  before update on public.training_programs
  for each row
  execute function public.set_updated_at();

alter table public.training_programs enable row level security;
alter table public.training_programs force row level security;

create policy training_programs_select on public.training_programs for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy training_programs_write on public.training_programs for all to authenticated
  using (public.can_manage_employees(tenant_id))
  with check (public.can_manage_employees(tenant_id));

-- Requirements are tenant-configurable by role and/or site — never a
-- hard-coded regulation list, matching the same principle as Phase N's
-- compliance_requirements.
create table public.training_requirements (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  training_program_id uuid not null references public.training_programs (id) on delete cascade,
  required_for_role   public.user_role,
  required_for_site_id uuid references public.sites (id) on delete cascade,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  check (required_for_role is not null or required_for_site_id is not null)
);

create index training_requirements_tenant_id_idx on public.training_requirements (tenant_id);
create index training_requirements_program_idx on public.training_requirements (training_program_id);

create or replace function public.validate_training_requirement_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.training_programs p where p.id = new.training_program_id and p.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: training program % does not belong to tenant %', new.training_program_id, new.tenant_id;
  end if;
  if new.required_for_site_id is not null and not exists (select 1 from public.sites s where s.id = new.required_for_site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.required_for_site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger training_requirements_validate_tenant_refs
  before insert or update on public.training_requirements
  for each row
  execute function public.validate_training_requirement_tenant_refs();

alter table public.training_requirements enable row level security;
alter table public.training_requirements force row level security;

create policy training_requirements_select on public.training_requirements for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy training_requirements_write on public.training_requirements for all to authenticated
  using (public.can_manage_employees(tenant_id))
  with check (public.can_manage_employees(tenant_id));

create table public.training_enrollments (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  training_program_id   uuid not null references public.training_programs (id) on delete cascade,
  employee_id           uuid not null references public.employees (id) on delete cascade,
  status                public.training_enrollment_status not null default 'scheduled',
  enrolled_at           timestamptz not null default now(),
  completed_at          timestamptz,
  result                text,
  resulting_qualification_id uuid references public.employee_qualifications (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.training_enrollments is
  'status/completed_at are server-derived (enroll_employee_training()/complete_employee_training() RPCs only).';

create index training_enrollments_tenant_id_idx on public.training_enrollments (tenant_id);
create index training_enrollments_employee_id_idx on public.training_enrollments (employee_id);
create index training_enrollments_program_idx on public.training_enrollments (training_program_id);

create trigger training_enrollments_set_updated_at
  before update on public.training_enrollments
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_training_enrollment_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.training_programs p where p.id = new.training_program_id and p.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: training program % does not belong to tenant %', new.training_program_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger training_enrollments_validate_tenant_refs
  before insert or update on public.training_enrollments
  for each row
  execute function public.validate_training_enrollment_tenant_refs();

alter table public.training_enrollments enable row level security;
alter table public.training_enrollments force row level security;

create policy training_enrollments_select on public.training_enrollments for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = training_enrollments.employee_id and e.profile_id = auth.uid())
    or public.can_manage_employees(tenant_id)
  );

-- No direct client write — enroll_employee_training()/complete_employee_
-- training() RPCs only.

create trigger training_enrollments_audit_log
  after insert or update on public.training_enrollments
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Performance reviews — finalisation is a hard lock enforced server-side,
-- not merely a UI convention.

create table public.performance_reviews (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  employee_id         uuid not null references public.employees (id) on delete cascade,
  reviewer_profile_id uuid references public.profiles (id) on delete set null,
  review_period_start date not null,
  review_period_end   date not null,
  status              public.performance_review_status not null default 'draft',
  overall_rating      numeric(2, 1) check (overall_rating is null or (overall_rating >= 1 and overall_rating <= 5)),
  manager_comments    text,
  employee_comments   text,
  finalized_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (review_period_end >= review_period_start)
);

comment on table public.performance_reviews is
  'status/finalized_at are server-derived (advance_performance_review()/finalize_performance_review() RPCs only). No column may be modified once status = finalized — enforced by performance_reviews_lock_finalized trigger, not merely hidden in the UI.';

create index performance_reviews_tenant_id_idx on public.performance_reviews (tenant_id);
create index performance_reviews_employee_id_idx on public.performance_reviews (employee_id);

create trigger performance_reviews_set_updated_at
  before update on public.performance_reviews
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_performance_review_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger performance_reviews_validate_tenant_ref
  before insert or update on public.performance_reviews
  for each row
  execute function public.validate_performance_review_tenant_ref();

create or replace function public.performance_reviews_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'finalized' then
    raise exception 'invalid_transition: a finalized performance review can never be modified';
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status = 'manager_review')
    or (old.status = 'manager_review' and new.status = 'employee_review')
    or (old.status = 'employee_review' and new.status = 'acknowledgement')
    or (old.status = 'acknowledgement' and new.status = 'finalized')
  ) then
    raise exception 'invalid_transition: cannot move performance review from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger performance_reviews_validate_transition_trigger
  before update on public.performance_reviews
  for each row
  execute function public.performance_reviews_validate_transition();

alter table public.performance_reviews enable row level security;
alter table public.performance_reviews force row level security;

create policy performance_reviews_select on public.performance_reviews for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = performance_reviews.employee_id and e.profile_id = auth.uid())
    or public.can_manage_employees(tenant_id)
  );

-- No direct client write — create_performance_review()/advance_
-- performance_review()/finalize_performance_review() RPCs only.

create trigger performance_reviews_audit_log
  after insert or update on public.performance_reviews
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Development actions — a permanent record, independent of any single
-- review (an employee's development plan outlives individual review
-- cycles).

create table public.development_actions (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  employee_id   uuid not null references public.employees (id) on delete cascade,
  review_id     uuid references public.performance_reviews (id) on delete set null,
  goal          text not null check (char_length(goal) > 0),
  owner_profile_id uuid references public.profiles (id) on delete set null,
  target_date   date,
  status        text not null default 'open' check (status in ('open', 'in_progress', 'completed')),
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index development_actions_tenant_id_idx on public.development_actions (tenant_id);
create index development_actions_employee_id_idx on public.development_actions (employee_id);

create trigger development_actions_set_updated_at
  before update on public.development_actions
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_development_action_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger development_actions_validate_tenant_ref
  before insert or update on public.development_actions
  for each row
  execute function public.validate_development_action_tenant_ref();

alter table public.development_actions enable row level security;
alter table public.development_actions force row level security;

create policy development_actions_select on public.development_actions for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = development_actions.employee_id and e.profile_id = auth.uid())
    or public.can_manage_employees(tenant_id)
  );

create policy development_actions_write on public.development_actions for all to authenticated
  using (public.can_manage_employees(tenant_id))
  with check (public.can_manage_employees(tenant_id));

create trigger development_actions_audit_log
  after insert or update on public.development_actions
  for each row
  execute function public.audit_log_from_trigger();
