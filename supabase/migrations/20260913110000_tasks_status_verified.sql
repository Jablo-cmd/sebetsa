-- Sebetsa Phase K — Tasks, Duties & Operational Workflows, migration 1 of 4.
--
-- Adds 'verified' to the existing task_status enum ahead of the rest of
-- Phase K (its own migration — Postgres requires ALTER TYPE ... ADD VALUE
-- to commit before the new value can be referenced elsewhere).

alter type public.task_status add value 'verified';

comment on type public.task_status is
  'open -> in_progress -> completed -> verified (supervisor confirmation). cancelled/escalated are reachable from open/in_progress. Enforced by tasks_validate_transition() (see the Phase K hardening migration).';
