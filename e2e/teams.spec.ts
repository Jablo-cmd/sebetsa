import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('lists teams with their site and status and opens the detail page', async ({ page, app }) => {
  await app.open('supervisor');
  await page.goto('/teams');
  await expect(page.getByRole('heading', { name: 'Teams' })).toBeVisible();
  await expect(page.getByRole('row', { name: /Tower A Day Team.*Harbour Point – Tower A.*active/ })).toBeVisible();
  await page.getByRole('link', { name: 'Tower A Day Team' }).click();
  await expect(page.getByRole('heading', { name: 'Tower A Day Team' })).toBeVisible();
  await expect(page.getByText('Thabo Nkosi')).toBeVisible();
  await expect(page.getByText('Lerato Mahlangu')).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('a manager creates a team with a site and a lead, with validation', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/teams');
  await page.getByRole('button', { name: 'Add team' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog.getByText(/name is required/i)).toBeVisible();

  await dialog.getByLabel('Team name').fill('Atrium Night Team');
  await dialog.getByLabel('Site').selectOption(ID.siteAtrium);
  await dialog.getByLabel('Team lead').fill('Sarah');
  await dialog.getByRole('button', { name: /Sarah van Wyk/ }).click();
  await expect(dialog.getByText('Selected: Sarah van Wyk')).toBeVisible();
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByRole('row', { name: /Atrium Night Team.*Main Atrium/ })).toBeVisible();
  expect(backend.find('teams', { name: 'Atrium Night Team' })).toMatchObject({ site_id: ID.siteAtrium, lead_employee_id: PERSONAS.supervisor.employeeId, tenant_id: ID.org, status: 'active' });
});

test('a manager adds and removes team members; existing members are not offered again', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/teams/${ID.teamTowerADay}`);
  await page.getByLabel('Add a member').fill('Thabo');
  await expect(page.getByRole('button', { name: /Thabo Nkosi/ })).toHaveCount(0);

  await page.getByLabel('Add a member').fill('Hannah');
  await page.getByRole('button', { name: /Hannah Botha/ }).click();
  await expect(page.getByRole('link', { name: /Hannah Botha/ })).toBeVisible();
  expect(backend.table('team_members').filter((m) => m.team_id === ID.teamTowerADay)).toHaveLength(3);

  await page.getByRole('link', { name: /Hannah Botha/ }).locator('xpath=ancestor::div[contains(@class,"justify-between")][1]').getByRole('button', { name: 'Remove' }).click();
  await expect(page.getByRole('link', { name: /Hannah Botha/ })).toHaveCount(0);
  expect(backend.table('team_members').filter((m) => m.team_id === ID.teamTowerADay)).toHaveLength(2);
});

test('a manager edits the team and archives and restores it', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/teams/${ID.teamTowerADay}`);
  await page.getByRole('button', { name: 'Edit details' }).click();
  await expect(page.getByRole('dialog').getByLabel('Team name')).toHaveValue('Tower A Day Team');
  await page.getByRole('dialog').getByLabel('Team name').fill('Tower A Early Team');
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('heading', { name: 'Tower A Early Team' })).toBeVisible();

  await page.getByRole('button', { name: 'Archive team' }).click();
  await expect(page.getByRole('button', { name: 'Restore team' })).toBeVisible();
  expect(backend.find('teams', { id: ID.teamTowerADay }).status).not.toBe('active');
  await page.getByRole('button', { name: 'Restore team' }).click();
  await expect(page.getByRole('button', { name: 'Archive team' })).toBeVisible();
  expect(backend.find('teams', { id: ID.teamTowerADay }).status).toBe('active');
});

test('failures when changing membership or status are shown', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/teams/${ID.teamTowerADay}`);
  backend.fault('team_members', { method: 'DELETE', times: 1 });
  await page.getByRole('button', { name: 'Remove' }).first().click();
  await expect(page.getByText('Failed to remove team member.')).toBeVisible();
  expect(backend.table('team_members').filter((m) => m.team_id === ID.teamTowerADay)).toHaveLength(2);

  backend.fault('teams', { method: 'PATCH', times: 1 });
  await page.getByRole('button', { name: 'Archive team' }).click();
  await expect(page.getByText('Failed to update the team.')).toBeVisible();
  expect(backend.find('teams', { id: ID.teamTowerADay }).status).toBe('active');
});

test('a team search failure is shown', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/teams/${ID.teamTowerADay}`);
  backend.fault('employees', { method: 'GET' });
  await page.getByLabel('Add a member').fill('Han');
  await expect(page.getByText('Failed to search employees.')).toBeVisible();
});

test('read-only roles see the team but cannot change it', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto(`/teams/${ID.teamTowerADay}`);
  await expect(page.getByRole('heading', { name: 'Tower A Day Team' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Edit details' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Remove' })).toHaveCount(0);
  await expect(page.getByLabel('Add a member')).toHaveCount(0);
  await page.goto('/teams');
  await expect(page.getByRole('button', { name: 'Add team' })).toHaveCount(0);
});

test('an unknown team is "not found"; employees cannot open teams', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/teams/00000000-0000-4000-8000-00ee00000003');
  await expect(page.getByText('Team not found')).toBeVisible();
  await app.open('employee');
  await page.goto('/teams');
  await expect(page).not.toHaveURL(/teams/);
});
