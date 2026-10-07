-- ops_health(): service_role only, counts and ages only (no PII). One transaction, rolled back.
begin;

set local role service_role;
do $$
declare h jsonb;
begin
  h := public.ops_health();
  if h->>'database' <> 'ok' then raise exception 'FAIL: database not ok'; end if;
  if jsonb_typeof(h->'jobs') <> 'array' or jsonb_typeof(h->'jobs_never_ran') <> 'array' then raise exception 'FAIL: shape'; end if;
  if (h->'jobs_never_ran') ? 'recurring_tasks' is not true then raise exception 'FAIL: never-ran jobs not reported on a fresh database'; end if;
  if not (h->'notifications' ? 'dead_letter' and h->'notifications' ? 'pending_overdue' and h->'security' ? 'failures_1h') then raise exception 'FAIL: missing counters'; end if;
  -- no destinations, bodies or ids leak into the snapshot
  if h::text ~* '(@|destination|body|recipient)' then raise exception 'FAIL: snapshot contains personal-looking data: %', h; end if;
  raise notice 'PASS: ops_health reports job and notification state without personal data';
end $$;

reset role;
do $$
declare v_role text; v_ok boolean;
begin
  foreach v_role in array array['authenticated', 'anon'] loop
    v_ok := false;
    begin
      execute format('set local role %I', v_role);
      perform public.ops_health();
      v_ok := true;
    exception when insufficient_privilege then null;
    end;
    reset role;
    if v_ok then raise exception 'SECURITY_FAILURE: % can call ops_health', v_role; end if;
  end loop;
  raise notice 'PASS: ops_health is service_role only';
end $$;

rollback;
