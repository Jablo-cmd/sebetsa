-- Guardian / Parent Invitation & Account Activation
--
-- Phase 1 audit finding: a guardian created via admin_create_guardian()
-- already has a fully live auth.users + auth.identities row (email
-- pre-confirmed, profiles.status = 'active') the moment they're created.
-- There is no "pending identity" to build. The real gap is that
-- admin_create_guardian()'s one-time temporary_password is discarded by
-- every frontend caller — nobody ever tells the guardian how to log in.
--
-- This migration does NOT reinvent authentication. It reuses the existing,
-- already-working supabase.auth.resetPasswordForEmail() mechanism (the same
-- one src/features/auth/services/authService.ts already uses for staff
-- "forgot password", tested via Inbucket in local dev, requiring zero new
-- SMTP/Edge Function infrastructure) as the actual credential-delivery
-- channel for guardians too. What THIS migration adds is the audit/status
-- layer Supabase's built-in recovery token doesn't give us: a queryable,
-- revocable, resendable invitation lifecycle, gated by the same
-- can_manage_learners() authority that already governs guardian creation
-- (see 20260824090000_guardian_management.sql) — no new permission is
-- introduced, matching that migration's own precedent of reusing
-- can_view_learners()/can_manage_learners() rather than inventing a
-- parallel guardian-specific security model.
--
-- Because Supabase's recovery link is generated and delivered by GoTrue
-- itself (not something this migration can hash/store a real secret for),
-- "revocable" and "expires" are enforced at the application boundary: the
-- guardian-facing accept_guardian_invitation()/get_my_guardian_invitation()
-- functions below re-check this table's status/expiry every time, even
-- though the underlying Supabase recovery session might still technically
-- be valid. A revoked or expired invitation therefore cannot be used to
-- activate an account even if the guardian still has the email in hand.

create type public.guardian_invitation_status as enum ('pending', 'accepted', 'revoked');

comment on type public.guardian_invitation_status is
  '''expired'' is deliberately not a stored value — it is a derived condition (status = pending and expires_at < now()), computed wherever this table is read, so no background job is needed to flip stale invitations.';

create table public.guardian_invitations (
  id                   uuid primary key default gen_random_uuid(),
  school_id            uuid not null references public.schools (id) on delete cascade,
  guardian_profile_id  uuid not null references public.profiles (id) on delete cascade,
  status               public.guardian_invitation_status not null default 'pending',
  invited_at           timestamptz not null default now(),
  expires_at           timestamptz not null,
  accepted_at          timestamptz,
  revoked_at           timestamptz,
  created_by           uuid references public.profiles (id) on delete set null,
  updated_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.guardian_invitations is
  'Audit/status trail for guardian account-activation invitations. Does not itself hold a usable secret — the actual activation link is a Supabase Auth recovery link sent via resetPasswordForEmail(); this table exists so staff can see/resend/revoke invitation state, which a bare Supabase recovery token cannot express. Never hard-deleted (no DELETE policy) to preserve the audit trail (spec: "do not delete historical invitation records").';

create index guardian_invitations_school_id_idx on public.guardian_invitations (school_id);
create index guardian_invitations_guardian_profile_id_idx on public.guardian_invitations (guardian_profile_id);

-- At most one PENDING invitation per guardian at a time — sending a new
-- invitation (or resending) must first supersede any existing pending row
-- (see send_guardian_invitation() below), never stack a second one.
create unique index guardian_invitations_one_pending_per_guardian
  on public.guardian_invitations (guardian_profile_id)
  where status = 'pending';

create trigger guardian_invitations_set_updated_at
  before update on public.guardian_invitations
  for each row
  execute function public.set_updated_at();

create trigger guardian_invitations_set_created_updated_by
  before insert or update on public.guardian_invitations
  for each row
  execute function public.set_created_updated_by();

-- Tenant-match guard, same shape as guardian_profile_details_validate_tenant():
-- SECURITY DEFINER because a caller with can_manage_learners() but no
-- general profiles-read grant must still be able to insert this row.
create or replace function public.guardian_invitations_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guardian_tenant_id uuid;
begin
  select tenant_id into v_guardian_tenant_id from public.profiles where id = new.guardian_profile_id;
  if v_guardian_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: guardian_profile_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger guardian_invitations_validate_tenant_trigger
  before insert or update on public.guardian_invitations
  for each row
  execute function public.guardian_invitations_validate_tenant();

alter table public.guardian_invitations enable row level security;
alter table public.guardian_invitations force row level security;

-- Staff visibility/management mirrors guardian_profile_details exactly:
-- the same actor set (school_owner, principal, admissions_officer,
-- platform admins) that can create/manage a guardian can see and manage
-- their invitation state. All writes actually happen inside the
-- SECURITY DEFINER functions below (which bypass RLS as table owner,
-- exactly like admin_create_guardian does for profiles/auth.users) — these
-- INSERT/UPDATE policies exist as defense-in-depth against any accidental
-- direct client-side table write bypassing the lifecycle rules those
-- functions enforce (superseding a prior pending invite, single-pending
-- constraint, status transitions), not as the primary write path.
create policy guardian_invitations_select on public.guardian_invitations
  for select to authenticated using (public.can_view_learners(school_id));
create policy guardian_invitations_insert on public.guardian_invitations
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy guardian_invitations_update on public.guardian_invitations
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

-- No guardian-self SELECT policy: the invited guardian never queries this
-- table directly. Their only access path is get_my_guardian_invitation(),
-- a SECURITY DEFINER function scoped strictly to auth.uid()'s own most
-- recent invitation — same "narrow RPC instead of a direct grant" pattern
-- is_learner_guardian() uses to avoid a self-referential RLS policy.

-- No DELETE policy anywhere — combined with FORCE ROW LEVEL SECURITY, hard
-- delete is impossible for any authenticated caller, same as every other
-- table in this schema.

-- ---------------------------------------------------------------------------
-- send_guardian_invitation — creates (or resends/supersedes) a pending
-- invitation for an existing guardian profile. Does NOT send the email
-- itself (Postgres has no route to GoTrue's mailer) — the frontend caller
-- is responsible for following this up with
-- supabase.auth.resetPasswordForEmail(email, { redirectTo: '.../activate-account' })
-- in the same user action, exactly mirroring how admin_create_guardian()
-- already hands a value back to the frontend to act on rather than doing
-- everything itself.
create or replace function public.send_guardian_invitation(
  p_guardian_profile_id uuid,
  p_expires_in_hours int default 72
)
returns public.guardian_invitations
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_guardian_tenant uuid;
  v_guardian_role public.user_role;
  v_guardian_status public.profile_status;
  v_row public.guardian_invitations;
begin
  select tenant_id, role, status into v_guardian_tenant, v_guardian_role, v_guardian_status
  from public.profiles where id = p_guardian_profile_id;

  if v_guardian_tenant is null then
    raise exception 'not_found: guardian profile does not exist';
  end if;

  if not public.can_manage_learners(v_guardian_tenant) then
    raise exception 'insufficient_privilege: cannot invite a guardian for this school';
  end if;

  if v_guardian_role not in ('parent', 'guardian') then
    raise exception 'invalid_role: target profile is not a guardian';
  end if;

  if v_guardian_status <> 'active' then
    raise exception 'inactive_account: guardian account is not active';
  end if;

  if p_expires_in_hours is null or p_expires_in_hours <= 0 then
    raise exception 'invalid_expiry: expires_in_hours must be positive';
  end if;

  -- Resend / re-invite: supersede any existing pending invitation rather
  -- than stacking a second one (also enforced by the partial unique index
  -- above — this UPDATE is what makes a resend actually succeed instead of
  -- hitting that constraint).
  update public.guardian_invitations
    set status = 'revoked', revoked_at = now(), updated_by = auth.uid()
    where guardian_profile_id = p_guardian_profile_id and status = 'pending';

  insert into public.guardian_invitations (
    school_id, guardian_profile_id, status, invited_at, expires_at, created_by, updated_by
  ) values (
    v_guardian_tenant, p_guardian_profile_id, 'pending', now(), now() + make_interval(hours => p_expires_in_hours), auth.uid(), auth.uid()
  )
  returning * into v_row;

  return v_row;
end;
$$;

comment on function public.send_guardian_invitation(uuid, int) is
  'Creates/resends a pending guardian invitation record. Caller must separately trigger supabase.auth.resetPasswordForEmail() to actually deliver the activation email — this function only manages the audit/lifecycle row.';

-- Explicit revoke-then-grant, not a bare grant relying on
-- 20260822000000_function_security_hardening.sql's closing "alter default
-- privileges ... revoke execute on functions from public" to already
-- protect new functions from anon: verified directly against a throwaway
-- postgres:16-alpine container (both with and without an explicit `for
-- role` clause) that this statement does NOT register a pg_default_acl
-- row and does NOT prevent PUBLIC/anon execute on functions created
-- afterward — has_function_privilege('anon', ...) still returns true. This
-- means every function added in every migration after that one (including
-- admin_create_guardian) is currently callable by anon in production. That
-- is a pre-existing gap outside this feature's scope to fix everywhere, so
-- it is called out in the implementation report instead — but every
-- function this migration adds gets its own explicit revoke so it isn't
-- exposed to the same gap.
revoke execute on function public.send_guardian_invitation(uuid, int) from public;
grant execute on function public.send_guardian_invitation(uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- revoke_guardian_invitation — administrative revoke of a pending
-- invitation. Cannot revoke one already accepted or already revoked (a
-- clear invalid_state, not a silent no-op) — mirrors the explicit-rejection
-- style change_learner_status()/terminate_employee() already use for
-- invalid transitions.
create or replace function public.revoke_guardian_invitation(p_invitation_id uuid)
returns public.guardian_invitations
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school_id uuid;
  v_status public.guardian_invitation_status;
  v_row public.guardian_invitations;
begin
  select school_id, status into v_school_id, v_status
  from public.guardian_invitations where id = p_invitation_id;

  if v_school_id is null then
    raise exception 'not_found: invitation does not exist';
  end if;

  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot revoke this invitation';
  end if;

  if v_status <> 'pending' then
    raise exception 'invalid_state: only a pending invitation can be revoked';
  end if;

  update public.guardian_invitations
    set status = 'revoked', revoked_at = now(), updated_by = auth.uid()
    where id = p_invitation_id
    returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function public.revoke_guardian_invitation(uuid) from public;
grant execute on function public.revoke_guardian_invitation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- get_my_guardian_invitation — the ONLY guardian-facing read path onto this
-- table. Called from the /activate-account page while the guardian holds a
-- temporary Supabase recovery session (auth.uid() = their own id), so it
-- can safely be scoped entirely to auth.uid() with no input parameters.
-- SECURITY DEFINER because a guardian mid-activation has no general
-- profiles/schools read grant yet to rely on — same rationale as
-- is_learner_guardian(). Returns the guardian's own name, school name, and
-- currently-linked ACTIVE children so the activation screen can show "this
-- covers Maria (Grade 1A)" before the guardian commits to a password,
-- without ever being able to see another guardian's data (the query is
-- hard-scoped to v_guardian_id = auth.uid() throughout).
create or replace function public.get_my_guardian_invitation()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_guardian_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_guardian_id is null then
    raise exception 'unauthenticated: no active session';
  end if;

  select jsonb_build_object(
    'guardianFirstName', p.first_name,
    'guardianLastName', p.last_name,
    'schoolName', s.name,
    'invitation', (
      select jsonb_build_object(
        'id', gi.id,
        'status', gi.status,
        'effectiveStatus', case
          when gi.status = 'pending' and gi.expires_at < now() then 'expired'
          else gi.status::text
        end,
        'expiresAt', gi.expires_at,
        'acceptedAt', gi.accepted_at
      )
      from public.guardian_invitations gi
      where gi.guardian_profile_id = v_guardian_id
      order by gi.created_at desc
      limit 1
    ),
    'children', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'firstName', l.first_name, 'lastName', l.last_name) order by l.first_name)
      from public.learner_guardians lg
      join public.learners l on l.id = lg.learner_id
      where lg.guardian_profile_id = v_guardian_id and lg.active
    ), '[]'::jsonb)
  )
  into v_result
  from public.profiles p
  join public.schools s on s.id = p.tenant_id
  where p.id = v_guardian_id;

  if v_result is null then
    raise exception 'not_found: guardian profile not found';
  end if;

  return v_result;
end;
$$;

revoke execute on function public.get_my_guardian_invitation() from public;
grant execute on function public.get_my_guardian_invitation() to authenticated;

-- ---------------------------------------------------------------------------
-- accept_guardian_invitation — marks the guardian's most recent invitation
-- accepted. Called AFTER supabase.auth.updateUser({ password }) succeeds
-- (never before — this must never mark an invitation consumed unless a
-- real password was actually set), so the frontend's ordering is: set
-- password, then accept, then sign out (mirroring ResetPasswordForm's
-- existing "sign out after updateUser so the user re-authenticates with
-- the new password" convention). Re-validates status/expiry itself rather
-- than trusting the earlier get_my_guardian_invitation() read, closing the
-- gap where an admin revokes the invitation in the seconds between the
-- guardian loading the activation page and submitting the form.
create or replace function public.accept_guardian_invitation()
returns public.guardian_invitations
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_guardian_id uuid := auth.uid();
  v_invitation_id uuid;
  v_status public.guardian_invitation_status;
  v_expires_at timestamptz;
  v_row public.guardian_invitations;
begin
  if v_guardian_id is null then
    raise exception 'unauthenticated: no active session';
  end if;

  select id, status, expires_at into v_invitation_id, v_status, v_expires_at
  from public.guardian_invitations
  where guardian_profile_id = v_guardian_id
  order by created_at desc
  limit 1;

  if v_invitation_id is null then
    raise exception 'not_found: no invitation found for this account';
  end if;

  if v_status = 'accepted' then
    raise exception 'already_accepted: this invitation has already been used';
  end if;

  if v_status = 'revoked' then
    raise exception 'invalid_state: this invitation has been revoked';
  end if;

  if v_expires_at < now() then
    raise exception 'expired: this invitation has expired';
  end if;

  update public.guardian_invitations
    set status = 'accepted', accepted_at = now(), updated_by = v_guardian_id
    where id = v_invitation_id
    returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function public.accept_guardian_invitation() from public;
grant execute on function public.accept_guardian_invitation() to authenticated;
