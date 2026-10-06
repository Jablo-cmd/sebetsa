-- Sebetsa enterprise security regression tests.
-- These are catalog-level invariants and require no customer/demo data.

do $$
declare
  missing_rls integer;
  missing_force integer;
begin
  select count(*) into missing_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity;

  select count(*) into missing_force
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relforcerowsecurity;

  call test_util.record(
    'all public tables enable RLS',
    missing_rls = 0,
    format('%s public tables without RLS', missing_rls)
  );

  call test_util.record(
    'all public tables force RLS',
    missing_force = 0,
    format('%s public tables without FORCE RLS', missing_force)
  );
end $$;

do $$
declare
  has_policy boolean;
begin
  select exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_deliveries'
  ) into has_policy;

  call test_util.record(
    'notification delivery table has RLS policy',
    has_policy,
    'notification_deliveries must remain tenant/user protected'
  );
end $$;

do $$
declare
  anon_exec boolean;
  authenticated_exec boolean;
begin
  select has_function_privilege('anon', 'public.claim_notification_deliveries(integer,text,integer)', 'EXECUTE')
    into anon_exec;
  select has_function_privilege('authenticated', 'public.claim_notification_deliveries(integer,text,integer)', 'EXECUTE')
    into authenticated_exec;

  call test_util.record(
    'notification claim RPC is not executable by anon',
    not anon_exec
  );
  call test_util.record(
    'notification claim RPC is not executable by authenticated',
    not authenticated_exec
  );
end $$;

do $$
declare
  storage_bucket boolean;
begin
  select to_regclass('storage.buckets') is not null into storage_bucket;
  call test_util.record(
    'employee document storage contract exists',
    storage_bucket,
    'storage bucket stub must exist before employee document migrations'
  );
end $$;
