-- Fixtures for the guardian emergency-contact-access regression suite
-- (20260805100000_guardian_emergency_contacts_access.sql). Builds on
-- 05_learner_fixtures.sql's existing learners and guardian link: Learner A
-- (11110000...0001, School A) is already linked to guardian/parent
-- 55555555 via learner_guardians; Learner B (22220000...0001, School B) has
-- no guardian link and belongs to a different tenant — used here for the
-- "guardian cannot view another learner's contacts" and cross-tenant checks.

insert into public.learner_emergency_contacts (id, school_id, learner_id, name, relationship, phone) values
  ('ec110000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
   'Naledi Guardian', 'mother', '+27821234567'),
  ('ec220000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22220000-0000-0000-0000-000000000001',
   'Sipho Guardian', 'father', '+27827654321');
