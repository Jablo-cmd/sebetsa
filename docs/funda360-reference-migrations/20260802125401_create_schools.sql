-- Milestone 3 — Multi-Tenant Foundation
-- Creates the `schools` table: the tenant root. Every other tenant-scoped
-- table in the system will carry a `tenant_id` that references schools.id.

create type public.school_type as enum ('public', 'private', 'independent');

create type public.school_status as enum ('pending', 'active', 'inactive', 'suspended');

create table public.schools (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null check (char_length(name) > 0),
  registration_number   text,
  education_department  text,
  school_type           public.school_type not null default 'public',
  province              text,
  district              text,
  emis_number           text,
  email                 text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone                 text,
  website               text,
  logo_url              text,
  address               text,
  timezone              text not null default 'Africa/Johannesburg',
  currency              text not null default 'ZAR',
  language              text not null default 'en',
  status                public.school_status not null default 'pending',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.schools is 'Tenant root. One row per school/institution onboarded onto Funda360.';
comment on column public.schools.emis_number is 'South African Education Management Information System identifier, where applicable.';

-- NULLs never collide under a UNIQUE constraint, so schools that don't yet
-- have a registration/EMIS number on file can still be created.
create unique index schools_registration_number_key
  on public.schools (registration_number)
  where registration_number is not null;

create unique index schools_emis_number_key
  on public.schools (emis_number)
  where emis_number is not null;

create index schools_status_idx on public.schools (status);

-- Generic updated_at maintenance, reused by every tenant-scoped table.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger schools_set_updated_at
  before update on public.schools
  for each row
  execute function public.set_updated_at();
