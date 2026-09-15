import { test, expect } from '@playwright/test';
import { fulfillJson } from './utils/mockAuth';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildEmployeeRow } from './utils/sebetsaData';

function buildDepartmentRow(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'department-1',
    tenant_id: '22222222-2222-2222-2222-222222222222',
    name: 'Operations',
    code: 'OPS',
    active: true,
    ...overrides,
  };
}

async function installEmployeesListMock(page: import('@playwright/test').Page, employees: unknown[]) {
  await page.route('**/rest/v1/employees*', async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() !== 'GET' || !url.searchParams.has('limit')) return route.fallback();
    await fulfillJson(route, employees);
  });
}

async function installDepartmentsListMock(page: import('@playwright/test').Page, departments: unknown[]) {
  await page.route('**/rest/v1/departments*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, departments);
  });
}

async function installEmployeeDetailMock(page: import('@playwright/test').Page, employee: unknown) {
  await page.route('**/rest/v1/employees*', async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() !== 'GET' || url.searchParams.has('limit')) return route.fallback();
    await fulfillJson(route, employee);
  });
}

test('site_manager can view the employees directory', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'site_manager' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeesListMock(page, [buildEmployeeRow({ first_name: 'Karabo', last_name: 'Mokoena' })]);

  await page.goto('/employees');
  await expect(page.getByRole('heading', { name: 'Employees' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Karabo Mokoena' })).toBeVisible();
});

test('site_manager cannot manage employees (view-only)', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'site_manager' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeesListMock(page, [buildEmployeeRow()]);

  await page.goto('/employees');
  await expect(page.getByRole('button', { name: 'Add employee' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Terminate' })).toHaveCount(0);
});

test('hr_user can create an employee', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeesListMock(page, []);

  await page.route('**/rest/v1/employees*', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    await fulfillJson(route, buildEmployeeRow({ id: 'employee-2', first_name: 'Palesa', last_name: 'Nkosi' }));
  });

  await page.goto('/employees');
  await page.getByRole('button', { name: 'Add employee' }).click();
  await page.getByLabel('First name').fill('Palesa');
  await page.getByLabel('Last name').fill('Nkosi');
  await page.getByLabel('Employee number').fill('EMP-0002');
  await page.getByLabel('Start date').fill('2026-02-01');
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('heading', { name: 'Add employee' })).toHaveCount(0);
});

test('hr_user can view an employee profile with full detail', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeeDetailMock(page, buildEmployeeRow({ first_name: 'Karabo', last_name: 'Mokoena' }));

  await page.goto('/employees/employee-1');
  await expect(page.getByRole('heading', { name: 'Karabo Mokoena' })).toBeVisible();
});

test('hr_user can terminate an employee', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'hr_user' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName !== 'terminate_employee') return false;
      await fulfillJson(route, buildEmployeeRow({ employment_status: 'terminated' }));
      return true;
    },
  });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeeDetailMock(page, buildEmployeeRow());

  await page.goto('/employees/employee-1');
  await page.getByRole('button', { name: 'Terminate' }).click();
  await page.getByLabel('Termination date').fill('2026-06-30');
  await page.getByRole('dialog').getByRole('button', { name: 'Terminate' }).click();

  await expect(page.getByRole('heading', { name: 'Terminate employee' })).toHaveCount(0);
});

test('hr_user can reactivate a terminated employee', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'hr_user' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName !== 'reactivate_employee') return false;
      await fulfillJson(route, buildEmployeeRow({ employment_status: 'active' }));
      return true;
    },
  });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeeDetailMock(page, buildEmployeeRow({ employment_status: 'terminated' }));

  await page.goto('/employees/employee-1');
  await page.getByRole('button', { name: 'Reactivate' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Reactivate' }).click();

  await expect(page.getByRole('heading', { name: 'Reactivate employee' })).toHaveCount(0);
});

test('hr_user can provision a login for an employee', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'hr_user' }),
    onRpc: async (fnName, _payload, route) => {
      if (fnName !== 'provision_employee_login') return false;
      await fulfillJson(route, [{ user_id: '66666666-6666-6666-6666-666666666666', temporary_password: 'Tmp9xQ2vLkZo1==' }]);
      return true;
    },
  });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeeDetailMock(page, buildEmployeeRow({ profile_id: null, email: 'karabo@sebetsa.example' }));

  await page.goto('/employees/employee-1');
  await page.getByRole('button', { name: 'Provision login' }).click();
  await page.getByLabel('Role').selectOption('employee');
  await page.getByRole('dialog').getByRole('button', { name: 'Provision login' }).click();

  await expect(page.getByText('Tmp9xQ2vLkZo1==')).toBeVisible();
});

test('an employee with no email cannot be provisioned a login', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeeDetailMock(page, buildEmployeeRow({ profile_id: null, email: null }));

  await page.goto('/employees/employee-1');
  await page.getByRole('button', { name: 'Provision login' }).click();
  await expect(page.getByText('has no work email on file')).toBeVisible();
  await expect(page.getByLabel('Role')).toHaveCount(0);
});

test('a role without employee.view is blocked from the employees section', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/employees');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('link', { name: 'Employees' })).toHaveCount(0);
});

test('hr_user can create a department', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);

  await page.route('**/rest/v1/departments*', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    return fulfillJson(route, buildDepartmentRow({ id: 'department-2', name: 'Finance' }));
  });

  await page.goto('/employees/departments');
  await page.getByRole('button', { name: 'Add department' }).click();
  await page.getByLabel('Name').fill('Finance');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('heading', { name: 'Add department' })).toHaveCount(0);
});

test('tenant isolation: the employees list only ever reflects the caller\'s own tenant scope', async ({ page }) => {
  // RLS (verified independently in supabase/rls-tests/) is the actual
  // tenant-isolation boundary — this only demonstrates that the client
  // renders exactly the rows its (tenant-scoped) query returns.
  await seedSebetsaSession(page, { role: 'site_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'site_manager' }) });
  await installDepartmentsListMock(page, [buildDepartmentRow()]);
  await installEmployeesListMock(page, [buildEmployeeRow({ first_name: 'Karabo', last_name: 'Mokoena' })]);

  await page.goto('/employees');
  await expect(page.getByRole('link', { name: 'Karabo Mokoena' })).toBeVisible();
  await expect(page.getByText(/other-tenant/)).toHaveCount(0);
});
