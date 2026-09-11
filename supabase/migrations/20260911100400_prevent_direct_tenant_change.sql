-- Sebetsa Phase C — carry forward the Funda360 tenant-escalation fix
-- (supabase/migrations/20260803140000_prevent_direct_tenant_change.sql) from
-- day one instead of discovering the same vulnerability again later:
-- profiles_update_own's `using (id = auth.uid()) with check (id = auth.uid())`
-- only constrains which row, not which columns, so without this trigger a
-- self-update could rewrite tenant_id and re-scope the caller into another
-- organization's data.

create or replace function public.prevent_direct_tenant_change()
returns trigger
language plpgsql
as $$
begin
  if new.tenant_id is distinct from old.tenant_id and coalesce(current_setting('app.allow_tenant_change', true), '') <> 'true' then
    raise exception 'insufficient_privilege: tenant_id can only be changed via a privileged SECURITY DEFINER function';
  end if;
  return new;
end;
$$;

comment on function public.prevent_direct_tenant_change() is
  'Blocks any change to profiles.tenant_id unless app.allow_tenant_change was set true (transaction-local) by a privileged SECURITY DEFINER function immediately before its own UPDATE.';

create trigger profiles_prevent_direct_tenant_change
  before update on public.profiles
  for each row
  execute function public.prevent_direct_tenant_change();
