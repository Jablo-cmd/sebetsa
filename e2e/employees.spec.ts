import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('hr_user can view the workforce directory, scoped to their own organisation', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto('/employees');
  await expect(page.getByRole('heading', { name: 'Employees' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Lerato Mahlangu' })).toBeVisible();
  await expect(page.getByRole('row')).toHaveCount(9); // header + 8 employees
  await expect(page.getByText('Rhea Rival')).toHaveCount(0);
  await expect(page.getByText('RV-0001')).toHaveCount(0);
});

test('searching and filtering narrow the directory using real queries', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees');
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toBeVisible();

  await page.getByLabel('Search employees').fill('Lerato');
  await expect(page.getByRole('link', { name: 'Lerato Mahlangu' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toHaveCount(0);
  expect(backend.requests.some((r) => r.table === 'employees' && /ilike/.test(r.query.or ?? ''))).toBe(true);

  await page.getByLabel('Search employees').fill('');
  await page.getByLabel('Filter by employment status').selectOption('terminated');
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toHaveCount(0);
  await expect(page.getByText('No employees match your filters.')).toBeVisible();
});

test('a supervisor can view employees but has no management controls', async ({ page, app }) => {
  await app.open('supervisor');
  await page.goto('/employees');
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Add employee' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Edit' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Terminate' })).toHaveCount(0);
});

test('hr_user creates an employee; the row is stored in their tenant and appears in the directory', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees');
  await page.getByRole('button', { name: 'Add employee' }).click();
  await page.getByLabel('First name').fill('Palesa');
  await page.getByLabel('Last name').fill('Sithole');
  await page.getByLabel('Employee number').fill('BW-0100');
  await page.getByLabel('Start date').fill('2026-09-21');
  await page.getByLabel('Email').fill('palesa.sithole@brightway.example');
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('heading', { name: 'Add employee' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Palesa Sithole' })).toBeVisible();
  const created = backend.find('employees', { employee_number: 'BW-0100' });
  expect(created.tenant_id).toBe(ID.org);
  expect(created.employment_status).toBe('active');
  const post = backend.requests.find((r) => r.method === 'POST' && r.table === 'employees');
  expect(post?.body).toMatchObject({ tenant_id: ID.org, first_name: 'Palesa' });
});

test('creating an employee validates required fields and sends nothing when invalid', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees');
  await page.getByRole('button', { name: 'Add employee' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('dialog').getByText(/required/i).first()).toBeVisible();
  expect(backend.requests.filter((r) => r.method === 'POST' && r.table === 'employees')).toEqual([]);
});

test('a duplicate employee number is rejected with a friendly message and the dialog stays open', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees');
  await page.getByRole('button', { name: 'Add employee' }).click();
  await page.getByLabel('First name').fill('Duplicate');
  await page.getByLabel('Last name').fill('Number');
  await page.getByLabel('Employee number').fill('BW-0008');
  await page.getByLabel('Start date').fill('2026-09-21');
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toHaveText('This already exists — please check for a duplicate entry.');
  await expect(page.getByRole('heading', { name: 'Add employee' })).toBeVisible();
  expect(backend.table('employees').filter((e) => e.employee_number === 'BW-0008')).toHaveLength(1);
});

test('hr_user can view an employee profile with full detail', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto(`/employees/${PERSONAS.employee.employeeId}`);
  await expect(page.getByRole('heading', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByText('Cleaning Operations')).toBeVisible();
  await expect(page.getByRole('definition').filter({ hasText: /^Cleaner$/ })).toBeVisible();
  await expect(page.getByText('Sarah van Wyk')).toBeVisible();
  await expect(page.getByText('Linked')).toBeVisible();
});

test('hr_user terminates and then reactivates an employee', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  const id = PERSONAS.employee_two.employeeId as string;
  await page.goto(`/employees/${id}`);

  await page.getByRole('button', { name: 'Terminate' }).click();
  await page.getByLabel('Termination date').fill('2026-09-30');
  await page.getByRole('dialog').getByRole('button', { name: 'Terminate' }).click();
  await expect(page.getByRole('heading', { name: 'Terminate employee' })).toHaveCount(0);
  expect(backend.find('employees', { id }).employment_status).toBe('terminated');
  expect(backend.find('employees', { id }).employment_end_date).toBe('2026-09-30');
  await expect(page.getByRole('button', { name: 'Reactivate' })).toBeVisible();

  await page.getByRole('button', { name: 'Reactivate' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Reactivate' }).click();
  await expect(page.getByRole('heading', { name: 'Reactivate employee' })).toHaveCount(0);
  expect(backend.find('employees', { id }).employment_status).toBe('active');
  expect(backend.find('employees', { id }).employment_end_date).toBeNull();
  expect(backend.table('audit_log').some((a) => a.action === 'employee_terminated' && a.entity_id === id)).toBe(true);
});

test('a failed termination keeps the dialog open and reports the problem', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  backend.fault('rpc:terminate_employee', { status: 500, message: 'database unavailable' });
  const id = PERSONAS.employee_two.employeeId as string;
  await page.goto(`/employees/${id}`);
  await page.getByRole('button', { name: 'Terminate' }).click();
  await page.getByLabel('Termination date').fill('2026-09-30');
  await page.getByRole('dialog').getByRole('button', { name: 'Terminate' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toBeVisible();
  expect(backend.find('employees', { id }).employment_status).toBe('active');
});

test('hr_user provisions a login; a one-time temporary password is shown and the employee is linked', async ({ page, app }) => {
  const backend = await app.open('hr_user', {
    customize: (t) => t.employees.push({ id: '00000000-0000-4000-8000-002100000050', tenant_id: ID.org, profile_id: null, employee_number: 'BW-0050', first_name: 'Pieter', last_name: 'Visser', email: 'pieter.visser@brightway.example', phone: null, department_id: ID.deptCleaning, position_id: ID.posCleaner, supervisor_id: null, region_id: ID.regionGauteng, home_site_id: null, employment_type: 'full_time', employment_status: 'active', employment_start_date: '2026-09-01', employment_end_date: null, created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z' }),
  });
  await page.goto('/employees/00000000-0000-4000-8000-002100000050');
  await expect(page.getByText('None', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Provision login' }).click();
  await page.getByLabel('Role').selectOption('employee');
  await page.getByRole('dialog').getByRole('button', { name: 'Provision login' }).click();

  await expect(page.getByText('Temp-Passw0rd-E2E!')).toBeVisible();
  const profile = backend.find('profiles', { email: 'pieter.visser@brightway.example' });
  expect(profile.role).toBe('employee');
  expect(profile.tenant_id).toBe(ID.org);
  expect(backend.find('employees', { employee_number: 'BW-0050' }).profile_id).toBe(profile.id);
});

test('an employee with no email on file cannot be provisioned a login', async ({ page, app }) => {
  await app.open('hr_user', {
    customize: (t) => {
      const e = t.employees.find((x) => x.id === PERSONAS.employee_two.employeeId);
      if (e) {
        e.profile_id = null;
        e.email = null;
      }
    },
  });
  await page.goto(`/employees/${PERSONAS.employee_two.employeeId}`);
  await page.getByRole('button', { name: 'Provision login' }).click();
  await expect(page.getByText('has no work email on file')).toBeVisible();
  await expect(page.getByLabel('Role')).toHaveCount(0);
});

test('hr_user can create a department and it is stored against their tenant', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees/departments');
  await page.getByRole('button', { name: 'Add department' }).click();
  await page.getByLabel('Name').fill('Specialised Cleaning');
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('heading', { name: 'Add department' })).toHaveCount(0);
  await expect(page.getByRole('cell', { name: 'Specialised Cleaning' })).toBeVisible();
  expect(backend.find('departments', { name: 'Specialised Cleaning' }).tenant_id).toBe(ID.org);
});

test('deleting a department clears it from employees instead of deleting them', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/employees/departments');
  await page.getByRole('row', { name: /Cleaning Operations/ }).getByRole('button', { name: 'Delete' }).click();

  await expect(page.getByRole('cell', { name: 'Cleaning Operations' })).toHaveCount(0);
  expect(backend.table('departments').some((d) => d.name === 'Cleaning Operations')).toBe(false);
  const thabo = backend.find('employees', { id: PERSONAS.employee.employeeId });
  expect(thabo.department_id).toBeNull();
});

test('an employee cannot reach the employees section', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/employees');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('link', { name: 'Employees', exact: true })).toHaveCount(0);
});
