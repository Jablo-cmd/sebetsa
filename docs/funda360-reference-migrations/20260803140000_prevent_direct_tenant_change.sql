-- Security Fix — profiles.tenant_id self-service escalation
--
-- Vulnerability (found during an independent architecture review, verified
-- against this repo's own migrations): `profiles_update_own` (Milestone 3,
-- 20260802125403_row_level_security.sql) grants `using (id = auth.uid())
-- with check (id = auth.uid())` — that predicate only constrains *which
-- row* a user may update, not *which columns*. Unlike `role` (protected by
-- prevent_direct_role_change() below) and self-`status` changes (protected
-- by prevent_self_status_change()), `tenant_id` had no equivalent trigger.
--
-- The column-level `grant update (first_name, last_name, phone,
-- avatar_url, status) ...` added in Milestone 5 deliberately excludes
-- `tenant_id`, but that migration's own header comment already documents
-- why a column grant alone doesn't stop this: Supabase projects grant
-- `authenticated` blanket table-level privileges by default, which
-- silently reopens whatever a narrower column grant tried to close.
--
-- Attack chain: any authenticated user, any role, could issue
--   patch /rest/v1/profiles?id=eq.<own-id>   { "tenant_id": "<other-school-id>" }
-- and satisfy both the USING and WITH CHECK clauses of profiles_update_own
-- (their own row, id unchanged) with nothing rejecting the tenant_id
-- change itself. Since current_tenant_id() (row_level_security.sql) reads
-- tenant_id directly from this same row, and every tenant-scoped RLS
-- policy in the system is built on current_tenant_id(), a successful write
-- here re-scopes the attacker into an arbitrary other school — a full
-- cross-tenant isolation breach, not merely an unwanted profile edit.
--
-- Fix: the exact same pattern already proven for `role` — a BEFORE UPDATE
-- trigger blocking any change to `tenant_id` unless a transaction-local
-- flag was set immediately beforehand by a privileged SECURITY DEFINER
-- function. No such function exists yet (nothing in this codebase has a
-- legitimate reason to move an existing user to a different tenant), so
-- in practice this blocks 100% of tenant_id changes today. The flag
-- mechanism is included anyway — not exercised by anything yet — purely
-- so a future, deliberate "transfer user to another school" admin
-- function can be added the same way admin_update_user_role() was, without
-- a second migration to introduce the trigger machinery itself.

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
  'Blocks any change to profiles.tenant_id unless app.allow_tenant_change was set true (transaction-local) by a privileged SECURITY DEFINER function immediately before its own UPDATE — same pattern as prevent_direct_role_change(). No function currently sets this flag, so this trigger blocks all tenant_id changes unconditionally today.';

create trigger profiles_prevent_direct_tenant_change
  before update on public.profiles
  for each row
  execute function public.prevent_direct_tenant_change();
