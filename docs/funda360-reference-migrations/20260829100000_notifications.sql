-- Notification Engine Foundation (FND-COM-001 / formerly tracked as
-- FND-ARCH-002 — see the Kanban grooming pass that merged them)
--
-- Zero notification infrastructure existed before this migration. This
-- builds the real, durable half of it (a `notifications` table, RLS, and
-- a SECURITY DEFINER write path) plus a working in-app surface — and is
-- explicit about what it deliberately does NOT do: actually send an
-- email. Sending mail requires a real provider (Resend/SendGrid/SES/etc.)
-- and API credentials this migration cannot invent, exactly the same
-- external-blocker shape as the live payment gateway
-- (20260828090000_fees_adjustments_and_refunds.sql's Finance Architecture
-- doc). `email_status` defaults to 'not_sent' and is the documented
-- insertion point a future Edge Function/worker would consume
-- (`where email_status = 'not_sent'`, attempt delivery, update to
-- 'sent'/'failed') — the abstraction is ready, the wiring is not, and
-- this migration does not pretend otherwise.
--
-- What IS real and working today: a notification row is created via the
-- SECURITY DEFINER create_notification() (never a direct client insert —
-- same trust boundary as write_audit_log/admin_create_user), the intended
-- recipient can see and mark it read via ordinary RLS, and this migration
-- wires the very first real producer — send_guardian_invitation() — so an
-- invited guardian gets a genuine in-app notification, not a demo stub.

create type public.notification_email_status as enum ('not_sent', 'sent', 'failed');

create table public.notifications (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid references public.schools (id) on delete cascade,
  recipient_profile_id  uuid not null references public.profiles (id) on delete cascade,
  type                  text not null check (char_length(type) > 0),
  title                 text not null check (char_length(title) > 0),
  body                  text not null check (char_length(body) > 0),
  related_entity_table  text,
  related_entity_id     uuid,
  link_path             text,
  email_status          public.notification_email_status not null default 'not_sent',
  read_at               timestamptz,
  created_at            timestamptz not null default now()
);

comment on table public.notifications is 'In-app notifications, addressed to exactly one recipient. email_status=not_sent is the documented hand-off point for a future real email integration (see migration header) — this table does not itself send mail.';
comment on column public.notifications.type is 'A short, stable machine-readable label (e.g. "guardian_invitation", future "fee_overdue"/"attendance_alert") — not free text.';
comment on column public.notifications.link_path is 'An optional in-app route the notification should navigate to when clicked (e.g. "/activate-account"). Not validated against the actual route table — the producing function is responsible for supplying a real path.';
comment on column public.notifications.read_at is 'NULL = unread. Set once, by the recipient reading it — see notifications_update_own policy.';

create index notifications_recipient_unread_idx on public.notifications (recipient_profile_id, read_at);
create index notifications_school_id_idx on public.notifications (school_id);
create index notifications_created_at_idx on public.notifications (created_at);

-- ---------------------------------------------------------------------------
-- create_notification — the sole write path. Not granted to `authenticated`
-- directly (same reasoning as write_audit_log): reachable only from inside
-- another SECURITY DEFINER function's own body. A future caller that needs
-- to let staff directly trigger a notification (e.g. FND-COM-003
-- announcements) should add its own authorization check in its own
-- function body, not rely on a broad grant here.

create or replace function public.create_notification(
  p_recipient_profile_id  uuid,
  p_type                  text,
  p_title                 text,
  p_body                  text,
  p_school_id             uuid default null,
  p_related_entity_table  text default null,
  p_related_entity_id     uuid default null,
  p_link_path             text default null
) returns public.notifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result public.notifications;
begin
  insert into public.notifications (
    school_id, recipient_profile_id, type, title, body, related_entity_table, related_entity_id, link_path
  ) values (
    p_school_id, p_recipient_profile_id, p_type, p_title, p_body, p_related_entity_table, p_related_entity_id, p_link_path
  )
  returning * into v_result;
  return v_result;
end;
$$;

comment on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) is
  'SECURITY DEFINER insertion point for notifications, called explicitly from inside a privileged RPC''s own body (e.g. send_guardian_invitation). Not granted to authenticated — a client picking its own notification recipient/content is a spoofing vector even though notification content itself is low-stakes.';

revoke execute on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) from public;

-- ---------------------------------------------------------------------------
-- RLS — a notification is addressed to exactly one person; visibility is
-- purely "is this mine", no staff/admin broad-visibility tier (unlike
-- audit_log, which is deliberately administrative). The UPDATE policy is
-- intentionally unrestricted-by-column (a recipient could in principle
-- rewrite their own already-delivered notification's title) rather than
-- trigger-guarded to read_at only, the way profiles.role is — there is no
-- downstream trust decision anywhere that depends on a notification's
-- content staying exactly as written, unlike a role or tenant_id, so the
-- extra defense-in-depth machinery would be protecting against a risk
-- that does not exist here.

alter table public.notifications enable row level security;
alter table public.notifications force row level security;

create policy notifications_select_own on public.notifications
  for select to authenticated using (recipient_profile_id = auth.uid());

create policy notifications_update_own on public.notifications
  for update to authenticated using (recipient_profile_id = auth.uid()) with check (recipient_profile_id = auth.uid());

-- No INSERT policy for `authenticated` — create_notification() is the only
-- write path (SECURITY DEFINER, bypasses RLS as table owner). No DELETE
-- policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible; a read notification simply stays read_at-populated.

-- ---------------------------------------------------------------------------
-- First real producer: send_guardian_invitation() now also notifies the
-- guardian in-app. Re-declared via `create or replace function` with its
-- exact prior body (20260827090000_guardian_invitations.sql) plus one
-- added call — that migration file is untouched.

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

  update public.guardian_invitations
    set status = 'revoked', revoked_at = now(), updated_by = auth.uid()
    where guardian_profile_id = p_guardian_profile_id and status = 'pending';

  insert into public.guardian_invitations (
    school_id, guardian_profile_id, status, invited_at, expires_at, created_by, updated_by
  ) values (
    v_guardian_tenant, p_guardian_profile_id, 'pending', now(), now() + make_interval(hours => p_expires_in_hours), auth.uid(), auth.uid()
  )
  returning * into v_row;

  perform public.create_notification(
    p_guardian_profile_id, 'guardian_invitation', 'Activate your Funda360 account',
    'You''ve been invited to access the Parent Portal — check your email to set your password and get started.',
    v_guardian_tenant, 'guardian_invitations', v_row.id, '/activate-account'
  );

  return v_row;
end;
$$;
