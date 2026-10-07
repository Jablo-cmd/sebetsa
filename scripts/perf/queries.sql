-- The page-level queries the app issues, expressed as plain SQL for measurement. One row per query:
-- name | sql. Keep in step with the services named in the comments.
-- T = tenant, S = a mid-sized site, E = the employee persona's employee id.
\set T '''00000000-0000-0000-0000-00000000aa01'''
\set S '''00000000-0000-0000-0003-000000000007'''
\set E '''00000000-0000-0000-0004-000000000001'''
select * from (values
 ('dashboard / reports: get_operational_metrics (30 d)',
  'select * from public.get_operational_metrics(' || :T || '::uuid, current_date - 30, current_date)'),
 ('dashboard: open + overdue task counts',
  'select count(*) filter (where status in (''open'',''in_progress'')) as open, count(*) filter (where status in (''open'',''in_progress'') and due_at < now()) as overdue from public.tasks where tenant_id = ' || :T),
 ('employee list: page 1 (25) ordered by name',
  'select * from public.employees where tenant_id = ' || :T || ' order by last_name, first_name limit 25'),
 ('employee list: exact count',
  'select count(*) from public.employees where tenant_id = ' || :T),
 ('employee list: name search (ilike)',
  'select * from public.employees where tenant_id = ' || :T || ' and (first_name ilike ''%tha%'' or last_name ilike ''%tha%'') order by last_name limit 25'),
 ('site list: page 1 (25) + count',
  'select s.*, count(*) over () from public.sites s where tenant_id = ' || :T || ' order by name limit 25'),
 ('attendance: one site, last 7 days (50)',
  'select * from public.attendance_records where tenant_id = ' || :T || ' and site_id = ' || :S || ' and clock_in_at >= now() - interval ''7 days'' order by clock_in_at desc limit 50'),
 ('scheduling: one site, one week',
  'select * from public.shifts where tenant_id = ' || :T || ' and site_id = ' || :S || ' and starts_at >= date_trunc(''week'', now()) and starts_at < date_trunc(''week'', now()) + interval ''7 days'' order by starts_at'),
 ('scheduling: employee''s own shifts, next 14 days',
  'select * from public.shifts where tenant_id = ' || :T || ' and employee_id = ' || :E || ' and starts_at >= now() order by starts_at limit 50'),
 ('tasks: manager list (open, by due date, 50)',
  'select * from public.tasks where tenant_id = ' || :T || ' and status in (''open'',''in_progress'') order by due_at nulls last limit 50'),
 ('tasks: employee''s own',
  'select * from public.tasks where tenant_id = ' || :T || ' and assignee_id = ' || :E || ' order by due_at limit 50'),
 ('leave: pending requests (50)',
  'select * from public.leave_requests where tenant_id = ' || :T || ' and status = ''pending'' order by start_date limit 50')
) as q(name, sql);
