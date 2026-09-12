-- Sebetsa Phase H — Leave & Absence, migration 1 of 6.
--
-- Adds the 'revoked' leave_status value ahead of the rest of Phase H.
-- Postgres requires ALTER TYPE ... ADD VALUE to commit in its own
-- transaction before the new value can be referenced by name (e.g. in a
-- CHECK, a comparison, or another DDL statement in the same migration run)
-- — hence this is a standalone migration rather than folded into the next
-- one. No historical migration is touched; this is purely additive.

alter type public.leave_status add value 'revoked';

comment on type public.leave_status is
  'pending -> {approved, rejected, cancelled}; approved -> revoked. All other transitions are rejected by leave_requests_validate_transition() (see the Phase H lifecycle migration).';
