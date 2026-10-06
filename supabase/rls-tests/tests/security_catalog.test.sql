-- Sebetsa security catalog invariants (no fixtures; recorded in test_util.results).

do $$
declare n integer;
begin
  select count(*) into n
  from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public';
  call test_util.record('anon holds no privileges on public tables', n = 0, format('%s anon table grants', n));

  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.prokind in ('f', 'p')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  call test_util.record('anon cannot execute any public function', n = 0, format('%s anon-executable functions', n));

  select count(*) into n
  from information_schema.role_table_grants
  where grantee = 'authenticated' and table_schema = 'public'
    and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER');
  call test_util.record('authenticated has no TRUNCATE/REFERENCES/TRIGGER on public tables', n = 0, format('%s grants', n));

  select count(*) into n
  from information_schema.role_table_grants
  where grantee = 'authenticated' and table_schema = 'public'
    and table_name in ('audit_log', 'notification_deliveries', 'user_scopes', 'sod_rules')
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  call test_util.record('authenticated cannot write audit/outbox/scope/SoD tables directly', n = 0, format('%s grants', n));
end $$;

do $$
declare n integer; names text;
begin
  select count(*), string_agg(p.proname, ', ') into n, names
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  call test_util.record('every SECURITY DEFINER function pins search_path', n = 0, coalesce(names, ''));
end $$;

do $$
declare ok boolean;
begin
  foreach ok in array array[
    not has_function_privilege('authenticated', 'public.compute_attendance_metrics(uuid)', 'EXECUTE'),
    not has_function_privilege('authenticated', 'public.assert_separation_of_duties(text,uuid[])', 'EXECUTE'),
    not has_function_privilege('authenticated', 'public.purge_audit_log(interval)', 'EXECUTE'),
    not has_function_privilege('authenticated', 'public.write_audit_log(uuid,uuid,text,text,uuid,jsonb,jsonb)', 'EXECUTE'),
    not has_function_privilege('authenticated', 'public.create_notification(uuid,text,text,text,uuid,text,uuid,text)', 'EXECUTE')
  ] loop
    exit when not ok;
  end loop;
  call test_util.record('internal helper functions are not executable by authenticated', ok);
end $$;

do $$
declare ok boolean;
begin
  select has_function_privilege('authenticated', 'public.current_tenant_id()', 'EXECUTE')
     and has_function_privilege('authenticated', 'public.can_access_site(uuid,uuid)', 'EXECUTE')
     and has_function_privilege('authenticated', 'public.approve_leave_request(uuid,text)', 'EXECUTE')
    into ok;
  call test_util.record('RLS helpers and client RPCs remain executable by authenticated', ok);
end $$;

do $$
declare n integer; names text;
begin
  select count(*), string_agg(c.conrelid::regclass::text || '(' || c.conname || ')', ', ') into n, names
  from pg_constraint c
  where c.contype = 'f' and c.connamespace = 'public'::regnamespace
    and not exists (
      select 1 from pg_index i
      where i.indrelid = c.conrelid
        and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] @> c.conkey
        and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] <@ c.conkey
    );
  call test_util.record('every foreign key has a covering index', n = 0, coalesce(names, ''));
end $$;

do $$
declare n integer;
begin
  select count(*) into n from pg_policies
  where schemaname = 'public' and permissive = 'RESTRICTIVE' and policyname like 'scope_restrict_%';
  call test_util.record('scope restrictive policies exist on the 8 operational tables', n = 8, format('%s policies', n));

  select count(*) into n from public.sod_rules where enforced;
  call test_util.record('all 12 separation-of-duties rules are enforced', n = 12, format('%s enforced rules', n));

  select count(*) into n from pg_trigger
  where not tgisinternal and tgname like '%\_sod\_guard';
  call test_util.record('separation-of-duties guards are installed', n = 10, format('%s guards', n));

  select count(*) into n from pg_trigger
  where not tgisinternal and tgrelid = 'public.audit_log'::regclass;
  call test_util.record('audit_log has append-only and enrichment triggers', n = 3, format('%s triggers', n));
end $$;
