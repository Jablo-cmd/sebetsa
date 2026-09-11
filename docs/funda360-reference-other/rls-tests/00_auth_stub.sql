-- Hand-built `auth` schema stub for RLS/trigger/SECURITY DEFINER
-- verification against a plain postgres:16-alpine container — there is no
-- real Supabase project involved. Provides just enough of GoTrue's schema
-- and JWT-resolution functions for the application's migrations to run
-- and be exercised exactly as PostgREST would exercise them in production:
-- `auth.users`, `auth.identities`, `auth.uid()`, `auth.jwt()`, and an
-- `authenticated` role with the same default blanket table grants a real
-- Supabase project sets outside of migration history (this is the exact
-- gotcha documented in 20260802151501_user_role_management.sql — a
-- column-level grant alone is not sufficient, because Supabase grants
-- `authenticated` full table privileges by default).
--
-- Run once per container, before applying supabase/migrations/*.sql.

create schema if not exists auth;

create table auth.users (
  instance_id uuid,
  id uuid primary key,
  aud text,
  role text,
  email text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmation_token text,
  recovery_token text,
  email_change_token_new text,
  email_change text
);

create table auth.identities (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  identity_data jsonb not null default '{}'::jsonb,
  provider text not null,
  provider_id text not null,
  last_sign_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Mirrors real Supabase: auth.uid() reads the `sub` claim, auth.jwt()
-- returns the full claims object, from the `request.jwt.claims` GUC that
-- PostgREST sets per-request from the caller's JWT. Tests below set this
-- GUC transaction-locally via set_config(...) to impersonate a given user.
create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;

create or replace function auth.jwt()
returns jsonb
language sql stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end;
$$;

grant usage on schema auth to authenticated;
grant usage on schema public to authenticated;
grant usage on schema public to anon;
grant execute on all functions in schema auth to authenticated;

-- Real Supabase projects grant both `authenticated` and `anon` blanket
-- table/sequence privileges by default, independent of anything a
-- migration explicitly grants — RLS, not table-level GRANT, is the real
-- boundary for row access. Reproduced here deliberately so a narrow
-- column-level GRANT in application migrations is never mistaken for real
-- protection — the same trap the project's own migration comments warn
-- about. Function EXECUTE privilege is deliberately NOT granted here to
-- either role beyond Postgres's own implicit PUBLIC-inherited default —
-- that default (present until a migration explicitly revokes it) is
-- exactly the behavior the function-security-hardening migration and its
-- tests are verifying.
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
alter default privileges in schema public grant all on tables to authenticated;
grant all on all tables in schema public to anon;
grant all on all sequences in schema public to anon;
alter default privileges in schema public grant all on tables to anon;
