-- Minimal stand-ins for the parts of the Supabase platform that Sebetsa's
-- migrations depend on but that a plain PostgreSQL image does not provide:
-- the `anon` / `service_role` API roles, Supabase's default object grants,
-- and the `storage` schema used by employee-document storage policies.
--
-- Supabase grants anon/authenticated/service_role broad table privileges
-- and EXECUTE on new public functions by default. Reproducing that here is
-- deliberate: a migration that forgets to REVOKE is then caught by the
-- grant assertions in tests/enterprise_security.test.sql instead of
-- passing only because the harness was stricter than production.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

grant usage on schema public to anon, service_role;
grant usage on schema auth to anon, service_role;
grant execute on all functions in schema auth to anon, service_role;

alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets (id),
  name text not null,
  owner uuid,
  created_at timestamptz not null default now()
);

alter table storage.objects enable row level security;
grant all on storage.objects to authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;

create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $fn$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1];
$fn$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;
