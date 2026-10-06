import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('an organisation administrator sees every user in their organisation and none from another', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/users');
  await expect(page.getByRole('heading', { name: 'Users' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Chris Client' })).toBeVisible();
  await expect(page.getByRole('row')).toHaveCount(10); // header + 9 users of this tenant
  await expect(page.getByText('Rhea Rival')).toHaveCount(0);
  await expect(page.getByText('rhea.rival@rivalservices.example')).toHaveCount(0);
});

test('searching filters users by name or email', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByLabel('Search users').fill('lerato');
  await expect(page.getByRole('link', { name: 'Lerato Mahlangu' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Thabo Nkosi' })).toHaveCount(0);
  await page.getByLabel('Search users').fill('harbourpoint');
  await expect(page.getByRole('link', { name: 'Chris Client' })).toBeVisible();
});

test('creating a user shows a one-time temporary password and stores the user in the admin\'s tenant', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('button', { name: 'Add user' }).click();
  await page.getByLabel('First name').fill('Naledi');
  await page.getByLabel('Last name').fill('Khumalo');
  await page.getByLabel('Email').fill('naledi.khumalo@brightway.example');
  await page.getByRole('dialog').getByLabel('Role').selectOption('site_manager');
  await page.getByRole('dialog').getByRole('button', { name: 'Create user' }).click();

  await expect(page.getByText('Temp-Passw0rd-E2E!')).toBeVisible();
  const created = backend.find('profiles', { email: 'naledi.khumalo@brightway.example' });
  expect(created.role).toBe('site_manager');
  expect(created.tenant_id).toBe(ID.org);
  const rpc = backend.requests.find((r) => r.rpc === 'admin_create_user');
  expect(rpc?.body).not.toHaveProperty('p_tenant_id'); // tenant comes from the caller, never the client
});

test('creating a user with an already-registered email is rejected with a clear message', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('button', { name: 'Add user' }).click();
  await page.getByLabel('First name').fill('Copy');
  await page.getByLabel('Last name').fill('Cat');
  await page.getByLabel('Email').fill(PERSONAS.employee.email);
  await page.getByRole('dialog').getByLabel('Role').selectOption('employee');
  await page.getByRole('dialog').getByRole('button', { name: 'Create user' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toHaveText('That email address is already registered.');
  expect(backend.table('profiles').filter((p) => p.email === PERSONAS.employee.email)).toHaveLength(1);
});

test('editing a user never sends tenant_id or role in the update payload', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Edit' }).click();
  await page.getByLabel('Phone').fill('0821234567');
  await page.getByRole('dialog').getByRole('button', { name: /Save/ }).click();

  await expect(page.getByRole('heading', { name: 'Edit user' })).toHaveCount(0);
  const patch = backend.requests.find((r) => r.method === 'PATCH' && r.table === 'profiles');
  expect(patch).toBeDefined();
  expect(Object.keys(patch?.body as object)).not.toContain('tenant_id');
  expect(Object.keys(patch?.body as object)).not.toContain('role');
  expect(backend.find('profiles', { id: PERSONAS.employee_two.profileId }).phone).toBe('0821234567');
});

test('an organisation administrator changes another user\'s role through the controlled RPC', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Change role' }).click();
  await page.getByRole('dialog').getByLabel('Role').selectOption('supervisor');
  await page.getByRole('button', { name: 'Confirm change' }).click();

  await expect(page.getByRole('heading', { name: 'Change role' })).toHaveCount(0);
  expect(backend.find('profiles', { id: PERSONAS.employee_two.profileId }).role).toBe('supervisor');
  expect(backend.requests.some((r) => r.method === 'PATCH' && r.table === 'profiles' && 'role' in (r.body as object))).toBe(false);
  expect(backend.table('audit_log').some((a) => a.action === 'role_changed' && a.entity_id === PERSONAS.employee_two.profileId)).toBe(true);
});

test('nobody can change their own role (separation of duties)', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('row', { name: /Olivia Okafor/ }).getByRole('button', { name: 'Change role' }).click();
  await page.getByRole('dialog').getByLabel('Role').selectOption('operations_manager');
  await page.getByRole('button', { name: 'Confirm change' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('profiles', { id: PERSONAS.organization_administrator.profileId }).role).toBe('organization_administrator');
});

test('deactivating a user marks them inactive and removes the Deactivate action', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Deactivate' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Deactivate' }).click();

  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Deactivate' })).toHaveCount(0);
  expect(backend.find('profiles', { id: PERSONAS.employee_two.profileId }).status).toBe('inactive');
  // Status changes go through the controlled RPC, never a direct table write.
  expect(backend.requests.some((r) => r.method === 'PATCH' && r.table === 'profiles' && 'status' in (r.body as object))).toBe(false);
  expect(backend.requests.some((r) => r.rpc === 'admin_set_user_status')).toBe(true);
});

test('a deactivated user can be reactivated', async ({ page, app }) => {
  const backend = await app.open('organization_administrator', {
    customize: (t) => {
      const p = t.profiles.find((x) => x.id === PERSONAS.employee_two.profileId);
      if (p) p.status = 'inactive';
    },
  });
  await page.goto('/users');
  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ })).toContainText('inactive');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Reactivate' }).click();

  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ })).toContainText('active');
  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Reactivate' })).toHaveCount(0);
  expect(backend.find('profiles', { id: PERSONAS.employee_two.profileId }).status).toBe('active');
});

test('nobody can deactivate their own account', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto('/users');
  await page.getByRole('row', { name: /Olivia Okafor/ }).getByRole('button', { name: 'Deactivate' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Deactivate' }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('profiles', { id: PERSONAS.organization_administrator.profileId }).status).toBe('active');
});

test('a user cannot manage someone more senior than themselves', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto('/users');
  await expect(page.getByRole('row', { name: /Olivia Okafor/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Olivia Okafor/ }).getByRole('button', { name: 'Edit' })).toHaveCount(0);
  await expect(page.getByRole('row', { name: /Olivia Okafor/ }).getByRole('button', { name: 'Change role' })).toHaveCount(0);
});

test('operations managers and employees cannot open user management', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/users');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('a user detail page for a user in another tenant shows nothing', async ({ page, app }) => {
  await app.open('organization_administrator');
  await page.goto(`/users/${ID.rivalProfile}`);
  await expect(page.getByText('Rhea Rival')).toHaveCount(0);
  await expect(page.getByText('rhea.rival@rivalservices.example')).toHaveCount(0);
});
