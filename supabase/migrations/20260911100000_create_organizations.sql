-- Sebetsa Phase C — Multi-Tenant Foundation
-- Creates `organizations`: the tenant root. Every tenant-scoped table in the
-- system carries a `tenant_id` that references organizations.id.
--
-- Pattern reused verbatim from the Funda360 platform foundation
-- (supabase/migrations/20260802125401_create_schools.sql) — only the
-- domain-specific columns change; the tenancy shape does not.

create type public.organization_status as enum ('pending', 'active', 'inactive', 'suspended');

create table public.organizations (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (char_length(name) > 0),
  registration_number text,
  industry        text,
  email           text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone           text,
  website         text,
  logo_url        text,
  address         text,
  timezone        text not null default 'Africa/Johannesburg',
  currency        text not null default 'ZAR',
  language        text not null default 'en',
  status          public.organization_status not null default 'pending',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.organizations is 'Tenant root. One row per client organization onboarded onto Sebetsa (e.g. Servest).';

create unique index organizations_registration_number_key
  on public.organizations (registration_number)
  where registration_number is not null;

create index organizations_status_idx on public.organizations (status);

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

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row
  execute function public.set_updated_at();
