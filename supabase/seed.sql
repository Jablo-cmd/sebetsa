-- Sebetsa deterministic local demo dataset.
-- Safe for local reset only. No production credentials or real people.
-- The seed is intentionally tenant-shaped: organization -> region -> client -> site
-- plus workforce structure and configurable staffing requirements.

insert into public.organizations (id, name, registration_number, industry, email, phone, address, status)
values ('00000000-0000-4000-8000-000000000001', 'Demo Facilities Group', 'DEMO-SEBETSA-001',
        'Facilities Management', 'demo@sebetsa.local', '+27000000000',
        'Johannesburg, Gauteng', 'active')
on conflict (id) do nothing;

insert into public.regions (id, tenant_id, name, code)
values ('00000000-0000-4000-8000-000000000010', '00000000-0000-4000-8000-000000000001',
        'Gauteng North', 'GP-N')
on conflict (id) do nothing;

insert into public.clients (id, tenant_id, region_id, name, industry, primary_contact_name, primary_contact_email, status)
values ('00000000-0000-4000-8000-000000000020', '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000010', 'Demo Property Group', 'Commercial Property',
        'Demo Contact', 'contact@demo.sebetsa.local', 'active')
on conflict (id) do nothing;

insert into public.sites (id, tenant_id, client_id, region_id, name, address, site_type, status)
values ('00000000-0000-4000-8000-000000000030', '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000020', '00000000-0000-4000-8000-000000000010',
        'Demo Business Park', 'Johannesburg, Gauteng', 'Commercial', 'active')
on conflict (id) do nothing;

insert into public.departments (id, tenant_id, name)
values ('00000000-0000-4000-8000-000000000040', '00000000-0000-4000-8000-000000000001', 'Operations')
on conflict (id) do nothing;

insert into public.positions (id, tenant_id, department_id, title)
values ('00000000-0000-4000-8000-000000000050', '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000040', 'Site Supervisor')
on conflict (id) do nothing;

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, email, phone,
  department_id, position_id, home_site_id, employment_type, employment_status
)
values (
  '00000000-0000-4000-8000-000000000060',
  '00000000-0000-4000-8000-000000000001',
  'DEMO-0001', 'Demo', 'Supervisor', 'supervisor@sebetsa.local', '+27000000001',
  '00000000-0000-4000-8000-000000000040',
  '00000000-0000-4000-8000-000000000050',
  '00000000-0000-4000-8000-000000000030',
  'full_time', 'active'
)
on conflict (id) do nothing;

insert into public.teams (id, tenant_id, site_id, name, lead_employee_id)
values ('00000000-0000-4000-8000-000000000070',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000030',
        'Demo Day Operations',
        '00000000-0000-4000-8000-000000000060')
on conflict (id) do nothing;

insert into public.team_members (team_id, employee_id, tenant_id)
values ('00000000-0000-4000-8000-000000000070',
        '00000000-0000-4000-8000-000000000060',
        '00000000-0000-4000-8000-000000000001')
on conflict (team_id, employee_id) do nothing;

insert into public.site_assignments (id, tenant_id, site_id, employee_id, role_on_site)
values ('00000000-0000-4000-8000-000000000080',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000030',
        '00000000-0000-4000-8000-000000000060',
        'Site Supervisor')
on conflict (id) do nothing;

insert into public.site_staffing_requirements (id, tenant_id, site_id, label, required_count)
values ('00000000-0000-4000-8000-000000000090',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000030',
        'Day shift operations', 4)
on conflict (id) do nothing;
