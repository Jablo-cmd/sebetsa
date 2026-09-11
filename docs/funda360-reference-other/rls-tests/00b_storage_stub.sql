-- Minimal stand-in for Supabase's platform-managed `storage` schema.
--
-- The RLS harness runs against a bare postgres:16-alpine image, which has
-- no storage extension at all — real Supabase Storage (buckets, objects,
-- their RLS enforcement, storage.foldername()) is a platform service, not
-- something `supabase/migrations/*.sql` creates. Without this stub, any
-- migration that declares a bucket or a storage.objects policy (see
-- 20260821100000_storage_buckets_and_documents.sql) would simply fail to
-- apply here with "relation storage.buckets does not exist".
--
-- This reproduces just enough of the real shape — storage.buckets,
-- storage.objects, storage.foldername() — for storage.objects RLS
-- policies to be exercised exactly as Postgres would evaluate them for
-- real, using the same `set local role authenticated` +
-- `request.jwt.claims` impersonation pattern every other test file in
-- this suite already uses. It does not attempt to reproduce the Storage
-- HTTP API itself (upload/download semantics, server-side
-- size/mime-type enforcement) — those are exercised by the e2e suite
-- against mocked network responses instead, not by this SQL-level harness.

create schema if not exists storage;

create table storage.buckets (
  id                  text primary key,
  name                text not null,
  public              boolean not null default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table storage.objects (
  id          uuid primary key default gen_random_uuid(),
  bucket_id   text references storage.buckets (id),
  name        text,
  owner       uuid,
  metadata    jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table storage.objects enable row level security;
alter table storage.objects force row level security;

-- Real Supabase's storage.foldername(name) returns every path segment
-- except the last (the object's own filename) — e.g.
-- foldername('school-a/logo') = {'school-a'}, foldername('a/b/file.pdf')
-- = {'a','b'}. Faithfully reproduced (not simplified) since every storage
-- RLS policy in this codebase depends on segment 1 being the tenant id.
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  v_parts text[];
begin
  v_parts := string_to_array(name, '/');
  return v_parts[1 : greatest(array_length(v_parts, 1) - 1, 0)];
end;
$$;

grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
