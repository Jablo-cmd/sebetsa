-- ============================================================================
--  FUNDA360 PUBLIC DEMO SEED — Local Supabase only
-- ============================================================================
--
-- Run automatically by `supabase db reset` against your local Docker
-- Postgres (started with `supabase start`). This file builds the complete
-- public demonstration dataset: three fictional schools (Auris Academy,
-- Riverside College, Mhlabeni High School) with a full academic structure,
-- staff, learners, guardians, attendance, assessments, fees, behaviour
-- records and timetables — enough for every implemented Funda360 module to
-- show real, coherent, relational data out of the box.
--
-- SAFETY: this file creates real auth.users rows protected only by a
-- shared, publicly-documented password printed right here in this
-- repository — that is fine for a throwaway local Docker container and
-- NEVER fine against a hosted/production Supabase project. Never point
-- VITE_SUPABASE_URL at a hosted project while using this seed file.
--
-- Every seeded login (staff and guardians alike) shares one password:
--   Funda360!DEMO-ONLY-2026
-- (the "DEMO-ONLY" marker is deliberate — unmistakable as a placeholder if
-- ever pasted elsewhere, same convention this repo's local-dev seed always
-- used.)
--
-- REPEATABLE BY DESIGN: every id in this file is derived deterministically
-- from a short school code via md5(...)::uuid, and every date is computed
-- relative to current_date rather than hard-coded — running
-- `supabase db reset` at any point in the future regenerates the exact same
-- structure with attendance/assessment history that still looks current.
--
-- See the bottom of this file for the full account directory.

do $$
begin
  raise notice '============================================================';
  raise notice ' FUNDA360 PUBLIC DEMO SEED — DO NOT USE AGAINST A REAL PROJECT';
  raise notice ' Every seeded account shares the password: Funda360!DEMO-ONLY-2026';
  raise notice ' If you are seeing this against a hosted Supabase project,';
  raise notice ' stop now and investigate — this file must never run there.';
  raise notice '============================================================';
end;
$$;

create extension if not exists pgcrypto;

-- ============================================================================
-- Helper #1: seed_person — creates a real, sign-in-capable identity
-- (auth.users + auth.identities + public.profiles) with the shared demo
-- password. Reused for every staff member and guardian created below.
-- Dropped automatically at the end of this session (pg_temp).
-- ============================================================================
create function pg_temp.seed_person(
  p_id      uuid,
  p_email   text,
  p_first   text,
  p_last    text,
  p_role    public.user_role,
  p_tenant  uuid,
  p_status  public.profile_status default 'active'
) returns void
language plpgsql
as $fn$
declare
  v_meta jsonb;
begin
  v_meta := case
    when p_tenant is null then
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'role', p_role)
    else
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'role', p_role, 'tenant_id', p_tenant)
  end;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email,
    crypt('Funda360!DEMO-ONLY-2026', gen_salt('bf')), now(),
    v_meta, jsonb_build_object('first_name', p_first, 'last_name', p_last),
    now(), now(), '', '', '', ''
  )
  on conflict (id) do nothing;

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), p_id, jsonb_build_object('sub', p_id::text, 'email', p_email),
    'email', p_id::text, now(), now(), now()
  )
  on conflict do nothing;

  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
  values (p_id, p_tenant, p_first, p_last, p_email, p_role, p_status)
  on conflict (id) do nothing;
end;
$fn$;

-- ============================================================================
-- Helper #1b: pick_name — deterministic pseudo-random pick from a name pool,
-- keyed by an arbitrary seed string. Used instead of a linear multiplier
-- (e.g. `pool[(i*7) % len + 1]`) for every first/last name selection below:
-- two linear functions of the same loop variable are only superficially
-- "varied" — the (first, surname) PAIR they produce is still fully
-- determined by that one variable, so it collapses to as few as
-- pool_size distinct combinations no matter how the multipliers are
-- chosen (verified the hard way while building this file). Hashing decorrelates
-- the two picks completely, so learner/teacher/guardian name combinations
-- actually vary across the full pool x pool space instead of repeating in
-- a visible pattern.
-- ============================================================================
create function pg_temp.pick_name(p_pool text[], p_seed text)
returns text
language sql
immutable
as $fn$
  select p_pool[(abs(('x' || substr(md5(p_seed), 1, 8))::bit(32)::int) % array_length(p_pool, 1)) + 1]
$fn$;

-- ============================================================================
-- Helper #2: seed_demo_school — builds one school's entire domain (academic
-- structure, departments, staff, learners, guardians, attendance,
-- assessments, fees, behaviour, timetable). Called once per school below
-- with school-specific names, subjects, fee amounts and leadership team.
-- ============================================================================
create function pg_temp.seed_demo_school(
  p_school_id        uuid,
  p_code             text,      -- short unique code, used to namespace every derived uuid
  p_email_domain     text,
  p_subjects         text[],    -- exactly 8: 7 core + 1 additional-language variant
  p_tuition          numeric,
  p_transport_fee    numeric,
  p_male_names       text[],
  p_female_names     text[],
  p_surnames         text[],
  p_owner_job_title  text,
  p_owner_first      text, p_owner_last      text,
  p_principal_first  text, p_principal_last  text,
  p_vp_first         text, p_vp_last         text,
  p_hr_first         text, p_hr_last         text,
  p_finance_first    text, p_finance_last    text,
  p_admissions_first text, p_admissions_last text,
  p_medical_first    text, p_medical_last    text,
  p_hod_first        text, p_hod_last        text
) returns void
language plpgsql
as $fn$
declare
  v_ay_id           uuid := md5(p_code || ':ay')::uuid;
  v_term_ids        uuid[];
  v_grade_names     text[] := array['Grade 8', 'Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'];
  v_grade_ids       uuid[];
  v_class_ids       uuid[];
  v_class_names     text[];
  v_subject_ids     uuid[];
  v_dept_names      text[] := array['Executive Management', 'Academic Affairs', 'Human Resources', 'Finance', 'Admissions', 'Student Wellness', 'Administration', 'Sports & Culture'];
  v_dept_ids        uuid[];

  v_owner_emp_id      uuid; v_owner_profile_id      uuid;
  v_principal_emp_id  uuid; v_principal_profile_id  uuid;
  v_vp_emp_id         uuid; v_vp_profile_id         uuid;
  v_hr_emp_id         uuid; v_hr_profile_id         uuid;
  v_finance_emp_id    uuid; v_finance_profile_id    uuid;
  v_admissions_emp_id uuid; v_admissions_profile_id uuid;
  v_medical_emp_id    uuid; v_medical_profile_id    uuid;
  v_hod_emp_id        uuid; v_hod_profile_id        uuid;

  v_teacher_profile_ids uuid[];
  v_teacher_emp_ids     uuid[];

  v_learner_ids     uuid[];
  v_assessed        int[] := array[1, 2, 3, 4];
  v_assessment_types public.assessment_type[] := array['test', 'assignment', 'examination']::public.assessment_type[];

  v_positive_cats text[] := array['Academic Excellence', 'Leadership', 'Community Service', 'Sportsmanship', 'Improved Effort'];
  v_negative_cats text[] := array['Late for Class', 'Incomplete Homework', 'Disruptive Behaviour', 'Uniform Violation', 'Disrespect to Staff'];
  v_severities    public.behaviour_severity[] := array['low', 'medium', 'high']::public.behaviour_severity[];

  v_period_start time[] := array['08:00', '08:45', '09:30', '10:15', '11:00', '11:45']::time[];
  v_period_end   time[] := array['08:45', '09:30', '10:15', '11:00', '11:45', '12:30']::time[];
  v_days         public.day_of_week[] := array['monday', 'tuesday', 'wednesday', 'thursday', 'friday']::public.day_of_week[];

  g int; ci int; li int; i int; s int; t int; term_idx int; k int; d int;
  v_slot0 int; v_day_idx int; v_period_idx int;
  v_class_label text; v_section text;
  v_first text; v_last text; v_email text; v_id uuid; v_emp_id uuid;
  v_dob date; v_age int; v_admission_date date; v_status public.learner_status;
  v_guardian_seq int := 0;
  v_g_id uuid; v_g_first text; v_g_last text; v_rel public.guardian_relationship_type; v_primary boolean;
  v_count int;
  v_assessment_id uuid; v_title text; v_atype public.assessment_type; v_adate date; v_max_mark int; v_mark int;
  v_charge_id uuid; v_due date; v_paid_terms int; v_new_admission boolean;
  v_bank_import_id uuid;
  v_learner_class_of int; -- class index a given flat learner index belongs to
  v_school_day_dates date[];
  v_walk date;
begin
  -- --------------------------------------------------------------------
  -- Academic year + terms (dates always relative to "now" so a reseed at
  -- any future date still looks current)
  -- --------------------------------------------------------------------
  insert into public.academic_years (id, school_id, name, start_date, end_date, is_active)
  values (v_ay_id, p_school_id, extract(year from current_date)::text || ' Academic Year',
          make_date(extract(year from current_date)::int, 1, 15),
          make_date(extract(year from current_date)::int, 12, 5),
          true);

  for term_idx in 1..4 loop
    v_term_ids[term_idx] := md5(p_code || ':term:' || term_idx)::uuid;
  end loop;

  insert into public.terms (id, academic_year_id, school_id, name, sequence, start_date, end_date, active) values
    (v_term_ids[1], v_ay_id, p_school_id, 'Term 1', 1, make_date(extract(year from current_date)::int, 1, 15), make_date(extract(year from current_date)::int, 3, 20), true),
    (v_term_ids[2], v_ay_id, p_school_id, 'Term 2', 2, make_date(extract(year from current_date)::int, 4, 8),  make_date(extract(year from current_date)::int, 6, 26), true),
    (v_term_ids[3], v_ay_id, p_school_id, 'Term 3', 3, make_date(extract(year from current_date)::int, 7, 21), make_date(extract(year from current_date)::int, 9, 25), true),
    (v_term_ids[4], v_ay_id, p_school_id, 'Term 4', 4, make_date(extract(year from current_date)::int, 10, 13), make_date(extract(year from current_date)::int, 12, 5), true);

  -- --------------------------------------------------------------------
  -- Grades + classes (5 grades x 2 classes = 10 classes)
  -- --------------------------------------------------------------------
  for g in 1..5 loop
    v_grade_ids[g] := md5(p_code || ':grade:' || g)::uuid;
    insert into public.grades (id, school_id, name, sort_order)
    values (v_grade_ids[g], p_school_id, v_grade_names[g], 7 + g);

    for k in 1..2 loop
      ci := (g - 1) * 2 + k;
      v_section := case when k = 1 then 'A' else 'B' end;
      v_class_label := v_grade_names[g] || v_section;
      v_class_ids[ci] := md5(p_code || ':class:' || ci)::uuid;
      v_class_names[ci] := v_class_label;
      insert into public.classes (id, grade_id, school_id, name, capacity)
      values (v_class_ids[ci], v_grade_ids[g], p_school_id, v_class_label, 32);
    end loop;
  end loop;

  -- --------------------------------------------------------------------
  -- Subjects (8)
  -- --------------------------------------------------------------------
  for s in 1..8 loop
    v_subject_ids[s] := md5(p_code || ':subject:' || s)::uuid;
    insert into public.subjects (id, school_id, name)
    values (v_subject_ids[s], p_school_id, p_subjects[s]);
  end loop;

  -- --------------------------------------------------------------------
  -- Departments (8)
  -- --------------------------------------------------------------------
  for s in 1..8 loop
    v_dept_ids[s] := md5(p_code || ':dept:' || s)::uuid;
    insert into public.departments (id, school_id, name)
    values (v_dept_ids[s], p_school_id, v_dept_names[s]);
  end loop;

  -- --------------------------------------------------------------------
  -- Leadership team (8 accounts, all with logins), inserted in
  -- reports-to order (each manager must exist before a report references
  -- it via reports_to_employee_id).
  -- --------------------------------------------------------------------
  v_owner_profile_id := md5(p_code || ':profile:owner')::uuid;
  v_owner_emp_id := md5(p_code || ':emp:owner')::uuid;
  perform pg_temp.seed_person(v_owner_profile_id, 'owner@' || p_email_domain, p_owner_first, p_owner_last, 'school_owner', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date)
  values (v_owner_emp_id, p_school_id, v_owner_profile_id, p_code || '-EMP-0001', p_owner_first, p_owner_last, 'owner@' || p_email_domain, v_dept_ids[1], p_owner_job_title, 'full_time', 'active', current_date - 9 * 365);

  v_principal_profile_id := md5(p_code || ':profile:principal')::uuid;
  v_principal_emp_id := md5(p_code || ':emp:principal')::uuid;
  perform pg_temp.seed_person(v_principal_profile_id, 'principal@' || p_email_domain, p_principal_first, p_principal_last, 'principal', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_principal_emp_id, p_school_id, v_principal_profile_id, p_code || '-EMP-0002', p_principal_first, p_principal_last, 'principal@' || p_email_domain, v_dept_ids[1], 'Principal', 'full_time', 'active', current_date - 7 * 365, v_owner_emp_id);

  v_vp_profile_id := md5(p_code || ':profile:vp')::uuid;
  v_vp_emp_id := md5(p_code || ':emp:vp')::uuid;
  perform pg_temp.seed_person(v_vp_profile_id, 'viceprincipal@' || p_email_domain, p_vp_first, p_vp_last, 'vice_principal', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_vp_emp_id, p_school_id, v_vp_profile_id, p_code || '-EMP-0003', p_vp_first, p_vp_last, 'viceprincipal@' || p_email_domain, v_dept_ids[1], 'Vice Principal', 'full_time', 'active', current_date - 5 * 365, v_principal_emp_id);

  v_hr_profile_id := md5(p_code || ':profile:hr')::uuid;
  v_hr_emp_id := md5(p_code || ':emp:hr')::uuid;
  perform pg_temp.seed_person(v_hr_profile_id, 'hr@' || p_email_domain, p_hr_first, p_hr_last, 'hr_manager', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_hr_emp_id, p_school_id, v_hr_profile_id, p_code || '-EMP-0004', p_hr_first, p_hr_last, 'hr@' || p_email_domain, v_dept_ids[3], 'HR Manager', 'full_time', 'active', current_date - 4 * 365, v_principal_emp_id);

  v_finance_profile_id := md5(p_code || ':profile:finance')::uuid;
  v_finance_emp_id := md5(p_code || ':emp:finance')::uuid;
  perform pg_temp.seed_person(v_finance_profile_id, 'finance@' || p_email_domain, p_finance_first, p_finance_last, 'finance_manager', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_finance_emp_id, p_school_id, v_finance_profile_id, p_code || '-EMP-0005', p_finance_first, p_finance_last, 'finance@' || p_email_domain, v_dept_ids[4], 'Finance Manager', 'full_time', 'active', current_date - 6 * 365, v_principal_emp_id);

  v_admissions_profile_id := md5(p_code || ':profile:admissions')::uuid;
  v_admissions_emp_id := md5(p_code || ':emp:admissions')::uuid;
  perform pg_temp.seed_person(v_admissions_profile_id, 'admissions@' || p_email_domain, p_admissions_first, p_admissions_last, 'admissions_officer', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_admissions_emp_id, p_school_id, v_admissions_profile_id, p_code || '-EMP-0006', p_admissions_first, p_admissions_last, 'admissions@' || p_email_domain, v_dept_ids[5], 'Admissions Officer', 'full_time', 'active', current_date - 3 * 365, v_principal_emp_id);

  v_medical_profile_id := md5(p_code || ':profile:medical')::uuid;
  v_medical_emp_id := md5(p_code || ':emp:medical')::uuid;
  perform pg_temp.seed_person(v_medical_profile_id, 'nurse@' || p_email_domain, p_medical_first, p_medical_last, 'medical_officer', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_medical_emp_id, p_school_id, v_medical_profile_id, p_code || '-EMP-0007', p_medical_first, p_medical_last, 'nurse@' || p_email_domain, v_dept_ids[6], 'School Nurse / Medical Officer', 'part_time', 'active', current_date - 4 * 365, v_principal_emp_id);

  v_hod_profile_id := md5(p_code || ':profile:hod')::uuid;
  v_hod_emp_id := md5(p_code || ':emp:hod')::uuid;
  perform pg_temp.seed_person(v_hod_profile_id, 'hod@' || p_email_domain, p_hod_first, p_hod_last, 'department_head', p_school_id);
  insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
  values (v_hod_emp_id, p_school_id, v_hod_profile_id, p_code || '-EMP-0008', p_hod_first, p_hod_last, 'hod@' || p_email_domain, v_dept_ids[2], 'Head of Department: Academics', 'full_time', 'active', current_date - 8 * 365, v_principal_emp_id);

  -- --------------------------------------------------------------------
  -- Teaching staff: 8 subject specialists (teacher t teaches subject t
  -- school-wide) + 2 extra homeroom-only staff, all reporting to the HOD.
  -- Teacher t is also the homeroom (class) teacher of class t (1:1, since
  -- there are exactly 10 teaching staff and 10 classes).
  -- --------------------------------------------------------------------
  for t in 1..10 loop
    if t % 2 = 0 then
      v_first := pg_temp.pick_name(p_male_names, p_code || ':teacher:mf:' || t);
    else
      v_first := pg_temp.pick_name(p_female_names, p_code || ':teacher:ff:' || t);
    end if;
    v_last := pg_temp.pick_name(p_surnames, p_code || ':teacher:sn:' || t);
    v_email := replace(lower(v_first), ' ', '') || '.' || replace(lower(v_last), ' ', '') || t || '@' || p_email_domain;
    v_id := md5(p_code || ':profile:teacher:' || t)::uuid;
    v_emp_id := md5(p_code || ':emp:teacher:' || t)::uuid;

    v_teacher_profile_ids[t] := v_id;
    v_teacher_emp_ids[t] := v_emp_id;

    perform pg_temp.seed_person(
      v_id, v_email, v_first, v_last,
      (case when t <= 8 then 'subject_teacher' else 'class_teacher' end)::public.user_role,
      p_school_id
    );

    insert into public.employees (id, school_id, profile_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, reports_to_employee_id)
    values (
      v_emp_id, p_school_id, v_id, p_code || '-EMP-' || lpad((8 + t)::text, 4, '0'), v_first, v_last, v_email,
      case when t = 9 then v_dept_ids[8] else v_dept_ids[2] end,
      case when t <= 8 then p_subjects[t] || ' Teacher' when t = 9 then 'Physical Education Coordinator' else 'Foundation Class Teacher' end,
      'full_time', 'active', current_date - ((2 + (t % 6)) * 365 + t * 11), v_hod_emp_id
    );
  end loop;

  -- --------------------------------------------------------------------
  -- Support staff (3, no portal login) — realistic HR-only records.
  -- One is intentionally 'terminated' to show the archive state.
  -- --------------------------------------------------------------------
  insert into public.employees (id, school_id, employee_number, first_name, last_name, work_email, department_id, job_title, employment_type, employment_status, hire_date, termination_date, reports_to_employee_id) values
    (md5(p_code || ':emp:support:1')::uuid, p_school_id, p_code || '-EMP-0019', p_female_names[2], p_surnames[2], 'reception@' || p_email_domain, v_dept_ids[7], 'Front Office Receptionist', 'full_time', 'active', current_date - 3 * 365, null, v_hr_emp_id),
    (md5(p_code || ':emp:support:2')::uuid, p_school_id, p_code || '-EMP-0020', p_male_names[3], p_surnames[3], 'facilities@' || p_email_domain, v_dept_ids[7], 'General Assistant', 'full_time', 'active', current_date - 6 * 365, null, v_hr_emp_id),
    (md5(p_code || ':emp:support:3')::uuid, p_school_id, p_code || '-EMP-0021', p_female_names[4], p_surnames[4], 'library@' || p_email_domain, v_dept_ids[2], 'Librarian', 'part_time', 'terminated', current_date - 4 * 365, current_date - 60, v_hr_emp_id);

  -- --------------------------------------------------------------------
  -- Class teacher assignments + timetable. Conflict-safe scheduling: each
  -- class owns its own room for every period it's in, so room conflicts
  -- are impossible; the slot formula guarantees no teacher or class is
  -- double-booked (see file header design notes / final report).
  -- --------------------------------------------------------------------
  for ci in 1..10 loop
    insert into public.class_teacher_assignments (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id)
    values (md5(p_code || ':cta:homeroom:' || ci)::uuid, p_school_id, v_ay_id, v_class_ids[ci], null, v_teacher_profile_ids[ci]);
  end loop;

  for s in 1..8 loop
    for ci in 1..10 loop
      insert into public.class_teacher_assignments (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id)
      values (md5(p_code || ':cta:subject:' || s || ':' || ci)::uuid, p_school_id, v_ay_id, v_class_ids[ci], v_subject_ids[s], v_teacher_profile_ids[s]);

      v_slot0 := ((ci - 1) * 7 + (s - 1)) % 30;
      v_day_idx := (v_slot0 / 6) + 1;
      v_period_idx := (v_slot0 % 6) + 1;

      insert into public.timetable_entries (id, school_id, academic_year_id, term_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values (
        md5(p_code || ':tt:' || s || ':' || ci)::uuid, p_school_id, v_ay_id, null, v_class_ids[ci], v_subject_ids[s], v_teacher_profile_ids[s],
        v_days[v_day_idx], v_period_start[v_period_idx], v_period_end[v_period_idx], v_class_names[ci]
      );
    end loop;
  end loop;

  -- --------------------------------------------------------------------
  -- Learners + enrollments + guardians + medical + documents + emergency
  -- contacts (10 classes x 12 learners = 120 per school)
  -- --------------------------------------------------------------------
  for ci in 1..10 loop
    g := ((ci - 1) / 2) + 1;

    for li in 1..12 loop
      i := (ci - 1) * 12 + li;

      if i % 2 = 0 then
        v_first := pg_temp.pick_name(p_male_names, p_code || ':learner:mf:' || i);
      else
        v_first := pg_temp.pick_name(p_female_names, p_code || ':learner:ff:' || i);
      end if;
      v_last := pg_temp.pick_name(p_surnames, p_code || ':learner:sn:' || i);

      v_age := 12 + g + (i % 2);
      v_dob := current_date - (v_age * 365 + (i * 13) % 300);
      v_admission_date := current_date - (300 + (i * 7) % 1500);
      v_status := (case when i % 25 = 0 then 'suspended' else 'active' end)::public.learner_status;

      v_id := md5(p_code || ':learner:' || i)::uuid;
      v_learner_ids[i] := v_id;

      insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, gender, home_language, status, admission_date)
      values (
        v_id, p_school_id, p_code || '-LRN-' || lpad(i::text, 4, '0'), p_code || '-ADM-' || lpad(i::text, 4, '0'),
        v_first, v_last, v_dob, case when i % 2 = 0 then 'male' else 'female' end,
        case when i % 3 = 0 then replace(p_subjects[8], ' First Additional Language', '') else 'English' end,
        v_status, v_admission_date
      );

      insert into public.learner_enrollments (id, school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date)
      values (md5(p_code || ':enrollment:' || i)::uuid, p_school_id, v_id, v_ay_id, v_grade_ids[g], v_class_ids[ci], v_admission_date);

      -- Medical info for every learner — mostly benign, a few with real notes
      insert into public.learner_medical_information (id, school_id, learner_id, allergies, medication, medical_conditions)
      values (
        md5(p_code || ':medical:' || i)::uuid, p_school_id, v_id,
        case (i % 9) when 0 then 'Peanuts' when 3 then 'Penicillin' when 6 then 'Bee stings' else null end,
        case (i % 9) when 0 then 'Epipen carried at all times' when 6 then 'Antihistamine as needed' else null end,
        case (i % 11) when 0 then 'Mild asthma (controlled)' when 5 then 'Type 1 diabetes' else null end
      );

      -- Birth certificate on file for every learner
      insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name, uploaded_at)
      values (
        md5(p_code || ':doc:birth:' || i)::uuid, p_school_id, v_id, 'birth_certificate',
        p_school_id::text || '/' || v_id::text || '/birth-certificate.pdf', v_first || '_' || v_last || '_birth_certificate.pdf',
        v_admission_date::timestamptz
      );

      -- Emergency contact (non-guardian) for a quarter of learners
      if i % 4 = 1 then
        insert into public.learner_emergency_contacts (id, school_id, learner_id, name, relationship, phone)
        values (md5(p_code || ':ec:' || i)::uuid, p_school_id, v_id, p_male_names[((i * 2) % array_length(p_male_names, 1)) + 1] || ' ' || v_last, 'Uncle', '+27 8' || lpad(((i * 37) % 100000000)::text, 8, '0'));
      end if;

      -- Guardians: learner #1 always gets 2 (the flagship parent-portal demo
      -- account); everyone else gets 2 (80%) or 1 (20%).
      v_count := case when i = 1 then 2 when i % 5 = 0 then 1 else 2 end;

      for k in 1..v_count loop
        v_guardian_seq := v_guardian_seq + 1;
        v_g_id := md5(p_code || ':guardian:' || v_guardian_seq)::uuid;

        if v_count = 1 then
          v_rel := (array['mother', 'father', 'legal_guardian', 'grandparent']::public.guardian_relationship_type[])[(i % 4) + 1];
          v_primary := true;
        elsif k = 1 then
          v_rel := 'mother'; v_primary := true;
        else
          v_rel := 'father'; v_primary := false;
        end if;

        if v_rel in ('mother', 'grandparent') and k != 2 then
          v_g_first := pg_temp.pick_name(p_female_names, p_code || ':guardian:ff:' || v_guardian_seq);
        elsif v_rel = 'father' then
          v_g_first := pg_temp.pick_name(p_male_names, p_code || ':guardian:mf:' || v_guardian_seq);
        else
          v_g_first := case when v_guardian_seq % 2 = 0 then pg_temp.pick_name(p_male_names, p_code || ':guardian:mf2:' || v_guardian_seq) else pg_temp.pick_name(p_female_names, p_code || ':guardian:ff2:' || v_guardian_seq) end;
        end if;
        v_g_last := case when k = 2 and v_guardian_seq % 7 = 0 then pg_temp.pick_name(p_surnames, p_code || ':guardian:sn:' || v_guardian_seq) else v_last end;

        if i = 1 and k = 1 then
          v_email := 'parent@' || p_email_domain;
        else
          v_email := replace(lower(v_g_first), ' ', '') || '.' || replace(lower(v_g_last), ' ', '') || v_guardian_seq || '@' || p_email_domain;
        end if;

        perform pg_temp.seed_person(v_g_id, v_email, v_g_first, v_g_last, 'guardian', p_school_id);

        if v_guardian_seq % 2 = 0 then
          insert into public.guardian_profile_details (id, school_id, guardian_profile_id, address, id_number)
          values (md5(p_code || ':gdetails:' || v_guardian_seq)::uuid, p_school_id, v_g_id, (10 + v_guardian_seq % 90) || ' ' || v_g_last || ' Street, ' || p_code, 'DEMO-ID-' || lpad(v_guardian_seq::text, 6, '0'));
        end if;

        insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary, is_emergency_contact, is_authorized_pickup)
        values (md5(p_code || ':lg:' || v_guardian_seq)::uuid, p_school_id, v_id, v_g_id, v_rel, v_primary, v_primary, true);

        if i = 1 and k = 1 then
          insert into public.guardian_invitations (id, school_id, guardian_profile_id, status, invited_at, expires_at, accepted_at)
          values (md5(p_code || ':ginv:' || v_guardian_seq)::uuid, p_school_id, v_g_id, 'accepted', now() - interval '30 days', now() - interval '23 days', now() - interval '29 days');
        elsif v_guardian_seq % 20 = 0 then
          insert into public.guardian_invitations (id, school_id, guardian_profile_id, status, invited_at, expires_at)
          values (md5(p_code || ':ginv:' || v_guardian_seq)::uuid, p_school_id, v_g_id, 'pending', now() - interval '2 days', now() + interval '1 day');
        elsif v_guardian_seq % 33 = 0 then
          insert into public.guardian_invitations (id, school_id, guardian_profile_id, status, invited_at, expires_at, revoked_at)
          values (md5(p_code || ':ginv:' || v_guardian_seq)::uuid, p_school_id, v_g_id, 'revoked', now() - interval '10 days', now() - interval '3 days', now() - interval '5 days');
        end if;
      end loop;
    end loop;
  end loop;

  -- --------------------------------------------------------------------
  -- Attendance: last 15 school weekdays for every class/learner
  -- --------------------------------------------------------------------
  v_school_day_dates := array[]::date[];
  v_walk := current_date;
  while array_length(v_school_day_dates, 1) is null or array_length(v_school_day_dates, 1) < 15 loop
    if extract(dow from v_walk) not in (0, 6) then
      v_school_day_dates := v_school_day_dates || v_walk;
    end if;
    v_walk := v_walk - 1;
  end loop;

  for ci in 1..10 loop
    for li in 1..12 loop
      i := (ci - 1) * 12 + li;
      for d in 1..array_length(v_school_day_dates, 1) loop
        insert into public.attendance_records (id, school_id, academic_year_id, class_id, learner_id, attendance_date, status)
        values (
          md5(p_code || ':att:' || i || ':' || d)::uuid, p_school_id, v_ay_id, v_class_ids[ci], v_learner_ids[i], v_school_day_dates[d],
          (case
            when (i + d) % 40 = 0 then 'absent'
            when (i + d) % 27 = 0 then 'late'
            when (i + d) % 31 = 0 then 'excused'
            else 'present'
          end)::public.attendance_status
        )
        on conflict do nothing;
      end loop;
    end loop;
  end loop;

  -- --------------------------------------------------------------------
  -- Assessments + results: 4 core subjects x 10 classes x 3 terms.
  -- Term 1 & 2 fully marked; Term 3 (current) ~70% marked (still in
  -- progress), giving the gradebook a realistic "not everything is done"
  -- texture.
  -- --------------------------------------------------------------------
  foreach s in array v_assessed loop
    for ci in 1..10 loop
      for term_idx in 1..3 loop
        v_atype := v_assessment_types[((s + ci + term_idx) % 3) + 1];
        v_adate := case term_idx when 1 then current_date - 150 + (ci % 5) when 2 then current_date - 70 + (ci % 5) else current_date - 8 + (ci % 3) end;
        v_max_mark := 100;
        v_title := p_subjects[s] || ' - Term ' || term_idx || ' ' || initcap(v_atype::text);
        v_assessment_id := md5(p_code || ':assess:' || s || ':' || ci || ':' || term_idx)::uuid;

        insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
        values (v_assessment_id, p_school_id, v_ay_id, v_term_ids[term_idx], v_class_ids[ci], v_subject_ids[s], v_title, v_atype, v_adate, v_max_mark);

        for li in 1..12 loop
          i := (ci - 1) * 12 + li;
          if term_idx < 3 or (li + ci) % 10 < 7 then
            v_mark := 40 + ((i * 17 + ci * 5 + term_idx * 3) % 56);
            insert into public.assessment_results (id, school_id, assessment_id, learner_id, mark)
            values (md5(p_code || ':result:' || s || ':' || ci || ':' || term_idx || ':' || li)::uuid, p_school_id, v_assessment_id, v_learner_ids[i], v_mark);
          end if;
        end loop;
      end loop;
    end loop;
  end loop;

  -- --------------------------------------------------------------------
  -- Fee-structure catalogue: a handful of reusable templates staff can
  -- pick from when charging a learner (previously defined in the schema
  -- but never surfaced anywhere in the product before this session).
  -- --------------------------------------------------------------------
  insert into public.fee_structures (id, school_id, academic_year_id, grade_id, name, category, amount, description) values
    (md5(p_code || ':fs:tuition')::uuid, p_school_id, v_ay_id, null, 'Term Tuition Fee', 'tuition', p_tuition, 'Standard per-term tuition, any grade.'),
    (md5(p_code || ':fs:transport')::uuid, p_school_id, v_ay_id, null, 'Term Transport Fee', 'transport', p_transport_fee, 'School transport, per term.'),
    (md5(p_code || ':fs:uniform')::uuid, p_school_id, v_ay_id, null, 'School Uniform Pack', 'uniform', 850, 'Full uniform set, new admissions.'),
    (md5(p_code || ':fs:activity')::uuid, p_school_id, v_ay_id, v_grade_ids[5], 'Grade 12 Farewell Levy', 'activity', 650, 'Matric farewell function contribution.');

  -- --------------------------------------------------------------------
  -- Fees: one tuition charge per term (1-3) per learner, plus a transport
  -- charge for ~30%. Payment coverage varies per learner for a realistic
  -- mix of fully paid / partially paid / outstanding accounts. A modest
  -- subset also gets a discount/bursary/scholarship/waiver adjustment
  -- and/or a refund against an existing payment, so the fee-adjustment
  -- and refund UI built this session has real demo content too.
  -- --------------------------------------------------------------------
  for i in 1..120 loop
    v_paid_terms := case i % 4 when 0 then 3 when 1 then 2 when 2 then 1 else 0 end;
    -- A small "joined this term" cohort gets ONLY a Term 3 charge — no
    -- Term 1/2 history at all. This is the only way Outstanding and
    -- Partially Paid can ever actually occur in this dataset: the app's
    -- overdue check looks at every charge on the account, paid or not, so
    -- any learner carrying a Term 1/2 charge (necessarily past-due by
    -- Term 3) reads as Overdue the moment any balance remains, regardless
    -- of which specific charge that balance belongs to — correct,
    -- intentional ledger-model behaviour (see calculations.ts), not
    -- something a due-date trick alone can route around for a returning
    -- learner.
    v_new_admission := (i % 16 = 0);

    if not v_new_admission then
      for term_idx in 1..2 loop
        v_due := current_date - (150 - (term_idx - 1) * 70);
        v_charge_id := md5(p_code || ':charge:tuition:' || i || ':' || term_idx)::uuid;
        insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, fee_structure_id, description, category, amount, due_date)
        values (v_charge_id, p_school_id, v_learner_ids[i], v_ay_id, md5(p_code || ':fs:tuition')::uuid, 'Term ' || term_idx || ' Tuition Fee', 'tuition', p_tuition, v_due);

        if term_idx <= v_paid_terms then
          insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method, reference)
          values (md5(p_code || ':payment:tuition:' || i || ':' || term_idx)::uuid, p_school_id, v_learner_ids[i], v_ay_id, p_tuition, v_due + 5, (array['eft', 'card', 'cash', 'debit_order']::public.fee_payment_method[])[((i + term_idx) % 4) + 1], 'RCPT-' || p_code || '-' || lpad(i::text, 4, '0') || '-' || term_idx);
        end if;
      end loop;
    end if;

    -- Term 3 (the "current" term — today falls within it) is due in the
    -- near future, not the past, so an unpaid Term 3 charge reads as
    -- "outstanding" rather than "overdue" for anyone with no other
    -- overdue charge on the account (i.e. the new-admission cohort).
    v_due := current_date + 20;
    v_charge_id := md5(p_code || ':charge:tuition:' || i || ':3')::uuid;
    insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, fee_structure_id, description, category, amount, due_date)
    values (v_charge_id, p_school_id, v_learner_ids[i], v_ay_id, md5(p_code || ':fs:tuition')::uuid, 'Term 3 Tuition Fee', 'tuition', p_tuition, v_due);

    if v_new_admission then
      -- Split the new-admission cohort three ways: unpaid (Outstanding),
      -- half-paid (Partially Paid), paid upfront (Paid).
      if i % 3 = 1 then
        insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method, reference)
        values (md5(p_code || ':payment:tuition:' || i || ':3partial')::uuid, p_school_id, v_learner_ids[i], v_ay_id, round(p_tuition * 0.5, 2), current_date - 3, 'eft', 'RCPT-' || p_code || '-' || lpad(i::text, 4, '0') || '-3P');
      elsif i % 3 = 2 then
        insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method, reference)
        values (md5(p_code || ':payment:tuition:' || i || ':3')::uuid, p_school_id, v_learner_ids[i], v_ay_id, p_tuition, current_date - 3, 'eft', 'RCPT-' || p_code || '-' || lpad(i::text, 4, '0') || '-3');
      end if;
    elsif v_paid_terms >= 3 then
      insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method, reference)
      values (md5(p_code || ':payment:tuition:' || i || ':3')::uuid, p_school_id, v_learner_ids[i], v_ay_id, p_tuition, current_date - 3, (array['eft', 'card', 'cash', 'debit_order']::public.fee_payment_method[])[(i % 4) + 1], 'RCPT-' || p_code || '-' || lpad(i::text, 4, '0') || '-3');
    end if;

    if i % 3 = 0 and not v_new_admission then
      insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, fee_structure_id, description, category, amount, due_date)
      values (md5(p_code || ':charge:transport:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, md5(p_code || ':fs:transport')::uuid, 'Term 3 Transport Fee', 'transport', p_transport_fee, current_date - 8);
    end if;

    -- Adjustments: sibling discount, bursary, rare scholarship/waiver.
    -- The discount ties to the Term 1 charge, which the new-admission
    -- cohort never has — fall back to a general account-level discount
    -- against the Term 3 charge (the one charge everyone always has).
    if i % 6 = 0 then
      insert into public.learner_fee_adjustments (id, school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, percentage, amount, reason)
      values (
        md5(p_code || ':adj:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id,
        case when v_new_admission then md5(p_code || ':charge:tuition:' || i || ':3')::uuid else md5(p_code || ':charge:tuition:' || i || ':1')::uuid end,
        'discount', 'percentage', 10, round(p_tuition * 0.10, 2),
        case when v_new_admission then 'Sibling discount — 10% off Term 3 tuition.' else 'Sibling discount — 10% off Term 1 tuition.' end
      );
    elsif i % 13 = 0 then
      insert into public.learner_fee_adjustments (id, school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, amount, reason)
      values (md5(p_code || ':adj:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, null, 'bursary', 'fixed_amount', round(p_tuition * 0.5, 2), 'Approved needs-based bursary, 50% of one term''s tuition.');
    elsif i % 29 = 0 then
      insert into public.learner_fee_adjustments (id, school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, amount, reason)
      values (md5(p_code || ':adj:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, null, 'scholarship', 'fixed_amount', p_tuition, 'Academic merit scholarship — one term''s tuition waived.');
    elsif i % 17 = 0 then
      insert into public.learner_fee_adjustments (id, school_id, learner_id, academic_year_id, charge_id, adjustment_type, method, amount, reason)
      values (md5(p_code || ':adj:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, null, 'waiver', 'fixed_amount', p_transport_fee, 'Transport fee waived — hardship case.');
    end if;

    -- Refunds: only for learners who actually paid Term 1 (v_paid_terms >= 1).
    if v_paid_terms >= 1 and i % 19 = 0 then
      insert into public.learner_fee_refunds (id, school_id, learner_id, academic_year_id, payment_id, amount, refund_date, method, reference, reason, status)
      values (md5(p_code || ':refund:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, md5(p_code || ':payment:tuition:' || i || ':1')::uuid, round(p_tuition * 0.2, 2), current_date - 20, 'eft', 'RFD-' || p_code || '-' || lpad(i::text, 4, '0'), 'Overpayment refunded after fee restructure.', case when i % 38 = 0 then 'pending' else 'completed' end::public.fee_refund_status);
    end if;
  end loop;

  -- --------------------------------------------------------------------
  -- Bank reconciliation: one uploaded statement per school with a mix of
  -- lines still to work through — several at the tuition amount (so the
  -- finance user has real recorded payments to match each against), one
  -- at the transport-fee amount, and two obvious bank charges to mark
  -- "ignored". Deliberately left all-unmatched: matching goes through
  -- reconcile_bank_statement_line() (needs an authenticated auth.uid()),
  -- and an untouched backlog is exactly what the demo should show.
  -- --------------------------------------------------------------------
  v_bank_import_id := md5(p_code || ':bankimport')::uuid;
  insert into public.bank_reconciliation_imports (id, school_id, file_name, imported_at)
  values (v_bank_import_id, p_school_id, 'bank-statement-' || to_char(current_date, 'YYYY-MM') || '.csv', now() - interval '2 days');

  for i in 1..5 loop
    insert into public.bank_statement_lines (id, school_id, import_id, transaction_date, description, amount)
    values (md5(p_code || ':bankline:tuition:' || i)::uuid, p_school_id, v_bank_import_id, current_date - (i + 2), 'EFT DEPOSIT - SCHOOL FEES REF ' || lpad(i::text, 4, '0'), p_tuition);
  end loop;
  insert into public.bank_statement_lines (id, school_id, import_id, transaction_date, description, amount)
  values (md5(p_code || ':bankline:transport')::uuid, p_school_id, v_bank_import_id, current_date - 4, 'EFT DEPOSIT - TRANSPORT', p_transport_fee);
  insert into public.bank_statement_lines (id, school_id, import_id, transaction_date, description, amount)
  values
    (md5(p_code || ':bankline:charge:1')::uuid, p_school_id, v_bank_import_id, current_date - 3, 'MONTHLY ACCOUNT ADMINISTRATION FEE', 57.00),
    (md5(p_code || ':bankline:charge:2')::uuid, p_school_id, v_bank_import_id, current_date - 3, 'CASH DEPOSIT FEE', 24.50);

  -- --------------------------------------------------------------------
  -- Behaviour incidents: a modest, realistic subset of learners
  -- --------------------------------------------------------------------
  -- Positive incidents are always shared to the parent portal; negative
  -- ones only for a subset (mirrors a real school sharing commendations
  -- freely but being more deliberate about what discipline detail parents
  -- see) — gives the demo Parent Portal's Behaviour tab real content
  -- without every incident automatically appearing there.
  for i in 1..120 loop
    if i % 7 = 0 then
      insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, category, occurred_at, description, action_taken, guardian_visible)
      values (md5(p_code || ':beh:pos:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, 'positive', v_positive_cats[(i % 5) + 1], now() - ((i % 40) || ' days')::interval, 'Recognised for outstanding conduct: ' || v_positive_cats[(i % 5) + 1] || '.', 'Merit certificate awarded in assembly.', true);
    end if;
    if i % 11 = 0 then
      insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, severity, category, occurred_at, description, action_taken, follow_up_required, guardian_visible)
      values (md5(p_code || ':beh:neg:' || i)::uuid, p_school_id, v_learner_ids[i], v_ay_id, 'negative', v_severities[(i % 3) + 1], v_negative_cats[(i % 5) + 1], now() - ((i % 25) || ' days')::interval, 'Incident recorded: ' || v_negative_cats[(i % 5) + 1] || '.', 'Verbal warning issued; parents notified.', i % 22 = 0, i % 33 = 0);
    end if;
  end loop;

  -- --------------------------------------------------------------------
  -- Admissions pipeline: a handful of learners not yet enrolled, so the
  -- admissions workflow has something to show beyond a fully-enrolled
  -- school.
  -- --------------------------------------------------------------------
  for i in 1..5 loop
    v_first := case when i % 2 = 0 then p_male_names[i] else p_female_names[i] end;
    v_last := p_surnames[array_length(p_surnames, 1) - i + 1];
    v_dob := current_date - ((12 + (i % 5)) * 365 + i * 19);
    insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date)
    values (
      md5(p_code || ':pipeline:' || i)::uuid, p_school_id, p_code || '-LRN-P' || lpad(i::text, 3, '0'), p_code || '-ADM-P' || lpad(i::text, 3, '0'),
      v_first, v_last, v_dob,
      (array['prospective', 'applied', 'accepted']::public.learner_status[])[((i - 1) % 3) + 1],
      current_date - (i * 5)
    );
  end loop;
end;
$fn$;

-- ============================================================================
-- School 1: Auris Academy — private, Cape Town, Western Cape
-- ============================================================================
insert into public.schools (id, name, registration_number, education_department, school_type, province, district, emis_number, email, phone, website, physical_address, postal_address, principal_name, status)
values (
  'a0000000-0000-0000-0000-000000000001', 'Auris Academy', 'WCED-2010-00456', 'Western Cape Education Department', 'private',
  'Western Cape', 'Cape Town Metro', '105011234', 'admin@auris.funda360.dev', '+27 21 555 0111', 'https://auris.funda360.dev',
  '14 Vineyard Close, Constantia, Cape Town, 7806', 'PO Box 1180, Constantia, 7848', 'Andrea Botha', 'active'
)
on conflict (id) do nothing;

select pg_temp.seed_demo_school(
  'a0000000-0000-0000-0000-000000000001', 'auris', 'auris.funda360.dev',
  array['Mathematics', 'English Home Language', 'Life Orientation', 'Physical Sciences', 'Social Sciences', 'Economic and Management Sciences', 'Technology', 'Afrikaans First Additional Language'],
  4500, 650,
  array['James', 'Michael', 'Daniel', 'Ethan', 'Ryan', 'Connor', 'Liam', 'Matthew', 'Jacques', 'Pieter', 'Stefan', 'Christo', 'Marco', 'Luke', 'Nicholas'],
  array['Emma', 'Chloe', 'Isabella', 'Zoe', 'Amy', 'Kayla', 'Lisa', 'Anika', 'Michelle', 'Sarah', 'Megan', 'Chantelle', 'Bianca', 'Robyn', 'Jessica'],
  array['Botha', 'Nel', 'Van der Merwe', 'Pretorius', 'Marais', 'Steyn', 'Fourie', 'Coetzee', 'Smith', 'Williams', 'Adams', 'Bosman', 'Kruger', 'Le Roux', 'Human'],
  'School Owner / Director',
  'Michael', 'Human',
  'Andrea', 'Botha',
  'Johan', 'Fourie',
  'Chantelle', 'Marais',
  'Pieter', 'Coetzee',
  'Lisa', 'Steyn',
  'Anika', 'Kruger',
  'Stefan', 'Nel'
);

-- ============================================================================
-- School 2: Riverside College — independent, Johannesburg, Gauteng
-- ============================================================================
insert into public.schools (id, name, registration_number, education_department, school_type, province, district, emis_number, email, phone, website, physical_address, postal_address, principal_name, status)
values (
  'b0000000-0000-0000-0000-000000000001', 'Riverside College', 'GDE-2012-00789', 'Gauteng Department of Education', 'independent',
  'Gauteng', 'Johannesburg Metro', '700109876', 'admin@riverside.funda360.dev', '+27 11 555 0222', 'https://riverside.funda360.dev',
  '58 Jan Smuts Avenue, Rosebank, Johannesburg, 2196', 'PO Box 2200, Rosebank, 2196', 'Thandiwe Nkosi', 'active'
)
on conflict (id) do nothing;

select pg_temp.seed_demo_school(
  'b0000000-0000-0000-0000-000000000001', 'riverside', 'riverside.funda360.dev',
  array['Mathematics', 'English Home Language', 'Life Orientation', 'Physical Sciences', 'Social Sciences', 'Economic and Management Sciences', 'Technology', 'IsiZulu First Additional Language'],
  2200, 450,
  array['Thabo', 'Sipho', 'Kagiso', 'Lwazi', 'Karabo', 'David', 'Ryan', 'Aiden', 'Arjun', 'Rohan', 'Tumelo', 'Katlego', 'Neo', 'Bongani', 'Sizwe'],
  array['Naledi', 'Palesa', 'Refilwe', 'Amahle', 'Zanele', 'Priya', 'Anisha', 'Emily', 'Grace', 'Lerato', 'Boitumelo', 'Thandiwe', 'Nomvula', 'Keitumetse', 'Aisha'],
  array['Mokoena', 'Dlamini', 'Nkosi', 'Khumalo', 'Mahlangu', 'Sithole', 'Naidoo', 'Pillay', 'Govender', 'Molefe', 'Radebe', 'Mabaso', 'Zulu', 'Van Wyk', 'Patel'],
  'School Owner / Director',
  'Karabo', 'Molefe',
  'Thandiwe', 'Nkosi',
  'Sipho', 'Dlamini',
  'Priya', 'Naidoo',
  'Rohan', 'Govender',
  'Naledi', 'Mokoena',
  'Zanele', 'Khumalo',
  'David', 'Radebe'
);

-- ============================================================================
-- School 3: Mhlabeni High School — public, Mpumalanga
-- ============================================================================
insert into public.schools (id, name, registration_number, education_department, school_type, province, district, emis_number, email, phone, website, physical_address, postal_address, principal_name, status)
values (
  'c0000000-0000-0000-0000-000000000001', 'Mhlabeni High School', 'MDE-2005-00321', 'Mpumalanga Department of Education', 'public',
  'Mpumalanga', 'Ehlanzeni', '800105678', 'admin@mhlabeni.funda360.dev', '+27 13 555 0333', 'https://mhlabeni.funda360.dev',
  '3 Kruger Road, Nelspruit, Mpumalanga, 1200', 'PO Box 330, Nelspruit, 1200', 'Sibusiso Nkosi', 'active'
)
on conflict (id) do nothing;

select pg_temp.seed_demo_school(
  'c0000000-0000-0000-0000-000000000001', 'mhlabeni', 'mhlabeni.funda360.dev',
  array['Mathematics', 'English Home Language', 'Life Orientation', 'Physical Sciences', 'Social Sciences', 'Economic and Management Sciences', 'Technology', 'SiSwati First Additional Language'],
  850, 300,
  array['Sibusiso', 'Mthunzi', 'Nkosinathi', 'Sanele', 'Mandla', 'Musa', 'Thulani', 'Bhekani', 'Sabelo', 'Wandile', 'Siyabonga', 'Vusi', 'Njabulo', 'Nhlanhla', 'Themba'],
  array['Nomthandazo', 'Sindisiwe', 'Nokuthula', 'Zanele', 'Ntombi', 'Busisiwe', 'Thandeka', 'Simphiwe', 'Precious', 'Lindiwe', 'Nolwazi', 'Ayanda', 'Fikile', 'Gugu', 'Zodwa'],
  array['Mahlangu', 'Nkosi', 'Dlamini', 'Simelane', 'Ngwenya', 'Shabalala', 'Mthembu', 'Khoza', 'Maseko', 'Mnisi', 'Zwane', 'Mabuza', 'Sithole', 'Kunene', 'Motha'],
  'School Administrator',
  'Nomthandazo', 'Mahlangu',
  'Sibusiso', 'Nkosi',
  'Thulani', 'Dlamini',
  'Busisiwe', 'Simelane',
  'Mandla', 'Ngwenya',
  'Sindisiwe', 'Shabalala',
  'Precious', 'Mthembu',
  'Vusi', 'Khoza'
);

-- ============================================================================
-- Platform-level Super Administrator (not scoped to any school)
-- ============================================================================
select pg_temp.seed_person(
  'f0000000-0000-0000-0000-000000000001', 'super.admin@funda360.dev', 'Lerato', 'Molefe', 'super_administrator', null
);

do $$
begin
  raise notice '============================================================';
  raise notice ' FUNDA360 DEMO SEED COMPLETE';
  raise notice ' 3 schools, 375 learners (360 enrolled + 15 admissions pipeline), 63 employees';
  raise notice ' ~650 guardians, ~703 total login accounts (staff + guardians + 1 platform admin)';
  raise notice ' Shared password for every account: Funda360!DEMO-ONLY-2026';
  raise notice ' See supabase/seed.sql header / final report for the full account directory.';
  raise notice '============================================================';
end;
$$;
