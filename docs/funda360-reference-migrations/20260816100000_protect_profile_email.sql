-- Sprint 3 Closure — profiles.email self-service escalation fix
--
-- Investigation performed before writing this fix: grepped the entire
-- frontend for every write to profiles.email. profileService.updateProfile
-- (self-service "My Profile" edit) and userService.updateUser (admin "Edit
-- User" modal) both take a ProfileUpdateInput that has never included an
-- `email` field. authService only ever writes `password` via
-- supabase.auth.updateUser({ password }). No email-change workflow exists
-- anywhere in this codebase today — profiles.email is set once, by
-- admin_create_user(), and is not currently intended to be user-editable at
-- all (Supabase Auth's own auth.users.email, not this column, is what a
-- real "change my email" feature would need to update first via a verified
-- flow).
--
-- This is the exact same class of bug already fixed for tenant_id
-- (20260803140000_prevent_direct_tenant_change.sql): profiles_update_own's
-- `using (id = auth.uid()) with check (id = auth.uid())` constrains which
-- row, not which columns, and Supabase's default blanket `authenticated`
-- table grants mean the column-level `grant update (...)` list in
-- 20260802151501_user_role_management.sql (which already deliberately
-- excludes `email`, per its own header comment) does not actually stop a
-- direct client PATCH of profiles.email. Any authenticated user could
-- currently rewrite their own profiles.email to an arbitrary value,
-- desynchronizing it from auth.users.email (the value Supabase Auth itself
-- treats as authoritative for login/notifications) and from the unique
-- index on lower(email) that the rest of the app relies on as a directory
-- key.
--
-- Fix: the same trigger pattern as tenant_id — not a blind copy, a
-- deliberate reuse of the same reasoning for the same reason. A BEFORE
-- UPDATE trigger blocks any change to `email` unless
-- app.allow_email_change was set true (transaction-local) by a privileged
-- SECURITY DEFINER function immediately beforehand. No such function
-- exists yet, so this blocks 100% of email changes today — matching
-- reality, since no legitimate email-change workflow exists in the
-- application yet. If one is added later (e.g. driven by Supabase Auth's
-- own verified email-change confirmation), it can call
-- set_config('app.allow_email_change', 'true', true) immediately before
-- its own UPDATE, without a further migration to add the trigger itself —
-- same extensibility reasoning as prevent_direct_tenant_change().

create or replace function public.prevent_direct_email_change()
returns trigger
language plpgsql
as $$
begin
  if new.email is distinct from old.email and coalesce(current_setting('app.allow_email_change', true), '') <> 'true' then
    raise exception 'insufficient_privilege: email can only be changed via a privileged, verified workflow';
  end if;
  return new;
end;
$$;

comment on function public.prevent_direct_email_change() is
  'Blocks any change to profiles.email unless app.allow_email_change was set true (transaction-local) by a privileged SECURITY DEFINER function immediately before its own UPDATE — same pattern as prevent_direct_tenant_change()/prevent_direct_role_change(). No function currently sets this flag, so this trigger blocks all email changes unconditionally today; no legitimate email-change workflow exists in the application yet.';

create trigger profiles_prevent_direct_email_change
  before update on public.profiles
  for each row
  execute function public.prevent_direct_email_change();
