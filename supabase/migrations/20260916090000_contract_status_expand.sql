-- Sebetsa Phase P — Client, Contract & SLA Management, migration 1 of 3.
--
-- New enum values only — Postgres forbids using a value added by ALTER TYPE
-- ... ADD VALUE inside the same transaction that added it (same rule
-- already applied to leave_status in Phase H), so the lifecycle trigger
-- that references these lives in its own, later migration file.

alter type public.contract_status add value 'expiring';
alter type public.contract_status add value 'suspended';
