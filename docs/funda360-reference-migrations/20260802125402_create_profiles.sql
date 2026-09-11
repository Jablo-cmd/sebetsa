-- Milestone 3 — Multi-Tenant Foundation
-- Creates `profiles`: personal/contact details for an authenticated user,
-- plus the `tenant_id` that scopes them to a school.
--
-- Deliberately excludes a `role` column. Per the RBAC & Security
-- Permissions Specification §4, role (and tenant_id, as a JWT claim) is
-- security-sensitive and lives in the JWT's `app_metadata`, set via an Auth
-- Hook — not in a user-editable table. `profiles.tenant_id` mirrors the JWT
-- claim for convenient querying/joins and is what Row Level Security below
-- relies on until that hook is configured.

create type public.profile_status as enum ('active', 'inactive', 'suspended');

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  tenant_id    uuid references public.schools (id) on delete set null,
  first_name   text not null check (char_length(first_name) > 0),
  last_name    text not null check (char_length(last_name) > 0),
  email        text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone        text,
  avatar_url   text,
  status       public.profile_status not null default 'active',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is 'Personal/contact details for an authenticated user, scoped to a tenant via tenant_id. Role is a JWT claim, not a column here.';
comment on column public.profiles.tenant_id is 'NULL for platform-level roles (super admin, platform admin) who are not scoped to a single school.';

create unique index profiles_email_key on public.profiles (lower(email));
create index profiles_tenant_id_idx on public.profiles (tenant_id);
create index profiles_status_idx on public.profiles (status);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();
