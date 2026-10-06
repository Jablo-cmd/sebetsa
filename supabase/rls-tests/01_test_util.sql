-- Minimal PL/pgSQL test-recording helper for the RLS harness. Each test is
-- a `do $$ ... $$` block that impersonates a user (set_config +
-- `set local role authenticated`, both transaction-local so they never
-- leak into the next test) and records a pass/fail row via
-- test_util.record(). run.sh fails the build if any row has passed=false.

create schema if not exists test_util;

create table test_util.results (
  id serial primary key,
  name text not null,
  passed boolean not null,
  detail text not null default ''
);

create or replace procedure test_util.record(p_name text, p_passed boolean, p_detail text default '')
language plpgsql
as $$
begin
  insert into test_util.results (name, passed, detail) values (p_name, p_passed, p_detail);
  raise notice '% — % %', case when p_passed then 'PASS' else 'FAIL' end, p_name,
    case when p_detail = '' then '' else '(' || p_detail || ')' end;
end;
$$;

create or replace function test_util.jwt_claims(p_user_id uuid, p_role text, p_tenant_id uuid)
returns text
language sql
stable
as $$
  select jsonb_build_object(
    'sub', p_user_id::text,
    'app_metadata', jsonb_build_object('role', p_role, 'tenant_id', p_tenant_id)
  )::text
$$;

-- Tests run impersonated as `authenticated` (see run.sh / test files), so
-- that role needs access to the recording helpers themselves — this is
-- harness plumbing, not part of what's under test.
grant usage on schema test_util to authenticated;
grant insert on test_util.results to authenticated;
grant usage, select on all sequences in schema test_util to authenticated;
grant execute on all functions in schema test_util to authenticated;
grant execute on all procedures in schema test_util to authenticated;
