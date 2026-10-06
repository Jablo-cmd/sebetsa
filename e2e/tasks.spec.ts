import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('My Tasks lists only my tasks, most urgent due date first', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/tasks');
  await expect(page.getByRole('heading', { name: 'My Tasks' })).toBeVisible();
  await expect(page.getByText('Deep clean staff kitchen')).toBeVisible();
  const titles = await page.getByRole('main').getByRole('button').allInnerTexts();
  const order = titles.map((t) => t.split('\n')[0]);
  expect(order.indexOf('Deep clean staff kitchen')).toBeLessThan(order.indexOf('Clean ground-floor washrooms'));
  await expect(page.getByText('Polish reception floor')).toHaveCount(0); // Lerato's task
});

test('a task cannot be completed until its checklist is done; completing records who and when', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/tasks');
  await page.getByRole('button', { name: /Clean ground-floor washrooms/ }).click();
  const dialog = page.getByRole('dialog', { name: 'Clean ground-floor washrooms' });
  await expect(dialog.getByText('Disinfect fixtures')).toBeVisible();

  await dialog.getByRole('button', { name: 'Mark complete' }).click();
  await expect(dialog.getByRole('alert')).toHaveText('All checklist items must be completed first.');
  expect(backend.find('tasks', { id: ID.taskWashrooms }).status).toBe('open');

  for (const label of ['Disinfect fixtures', 'Restock consumables', 'Mop floors']) {
    await dialog.getByLabel(label).click();
    await expect(dialog.getByLabel(label)).toBeChecked();
  }
  expect(backend.table('task_checklist_items').filter((i) => i.task_id === ID.taskWashrooms && i.is_completed)).toHaveLength(3);

  await dialog.getByRole('button', { name: 'Mark complete' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('tasks', { id: ID.taskWashrooms })).toMatchObject({ status: 'completed', completed_by: PERSONAS.employee.profileId });
  expect(backend.find('tasks', { id: ID.taskWashrooms }).completed_at).not.toBeNull();
});

test('a task that requires evidence is refused without it, and accepted once a note is added', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => {
      const task = t.tasks.find((x) => x.id === ID.taskKitchen);
      if (task) task.requires_evidence = true;
    },
  });
  await page.goto('/tasks');
  await page.getByRole('button', { name: /Deep clean staff kitchen/ }).click();
  const dialog = page.getByRole('dialog', { name: 'Deep clean staff kitchen' });
  await expect(dialog.getByText('(required)')).toBeVisible();

  await dialog.getByRole('button', { name: 'Mark complete' }).click();
  await expect(dialog.getByRole('alert')).toHaveText('Evidence must be attached before this task can be completed.');

  await dialog.getByLabel('Add a note').fill('Oven, fridge and surfaces cleaned; photo logged with supervisor');
  await dialog.getByRole('button', { name: 'Add evidence' }).click();
  await expect(dialog.getByText('Oven, fridge and surfaces cleaned')).toBeVisible();
  expect(backend.table('task_evidence').find((e) => e.task_id === ID.taskKitchen)).toMatchObject({ submitted_by: PERSONAS.employee.profileId, kind: 'note', tenant_id: ID.org });

  await dialog.getByRole('button', { name: 'Mark complete' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('tasks', { id: ID.taskKitchen }).status).toBe('completed');
});

test('a supervisor verifies completed work done by someone else', async ({ page, app }) => {
  const backend = await app.open('supervisor');
  await page.goto('/tasks/management');
  await expect(page.getByRole('heading', { name: 'Task Management' })).toBeVisible();
  await page.getByRole('row', { name: /Polish reception floor/ }).getByRole('button').click();
  await page.getByRole('dialog').getByRole('button', { name: 'Verify' }).click();

  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('tasks', { id: ID.taskReception }).status).toBe('verified');
  expect(backend.table('audit_log').some((a) => a.action === 'task_verified' && a.entity_id === ID.taskReception)).toBe(true);
});

test('a manager cannot verify a task they completed themselves', async ({ page, app }) => {
  const backend = await app.open('supervisor', {
    customize: (t) => {
      const task = t.tasks.find((x) => x.id === ID.taskReception);
      if (task) Object.assign(task, { assignee_id: PERSONAS.supervisor.employeeId, completed_by: PERSONAS.supervisor.profileId });
    },
  });
  await page.goto('/tasks/management');
  await page.getByRole('row', { name: /Polish reception floor/ }).getByRole('button').click();
  await page.getByRole('dialog').getByRole('button', { name: 'Verify' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('tasks', { id: ID.taskReception }).status).toBe('completed');
});

test('escalating overdue tasks flags only open overdue work and notifies the supervisor', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/tasks/management');
  await page.getByRole('button', { name: 'Escalate overdue' }).click();

  await expect(page.getByRole('row', { name: /Deep clean staff kitchen/ })).toContainText('Escalated');
  await expect(page.getByRole('row', { name: /Clean ground-floor washrooms/ })).not.toContainText('Escalated');
  expect(backend.find('tasks', { id: ID.taskKitchen }).status).toBe('escalated');
  expect(backend.find('tasks', { id: ID.taskWashrooms }).status).toBe('open');
  expect(backend.find('tasks', { id: ID.taskReception }).status).toBe('completed');
  expect(backend.table('notifications').some((n) => n.type === 'task_escalated' && n.recipient_profile_id === PERSONAS.supervisor.profileId)).toBe(true);
});

test('generating recurring tasks creates each template once per period', async ({ page, app }) => {
  const backend = await app.open('operations_manager', {
    customize: (t) =>
      t.task_templates.push({ id: '00000000-0000-4000-8000-003900000001', tenant_id: ID.org, site_id: ID.siteTowerA, title: 'Daily lobby sweep', description: null, instructions: 'Sweep and mop lobby', priority: 'normal', expected_duration_minutes: 30, requires_evidence: false, default_assignee_id: PERSONAS.employee.employeeId, default_team_id: null, recurrence_frequency: 'daily', status: 'active', last_generated_on: null, created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }),
  });
  await page.goto('/tasks/management');
  await page.getByRole('button', { name: 'Generate recurring tasks' }).click();
  await expect(page.getByRole('row', { name: /Daily lobby sweep/ })).toBeVisible();
  await page.getByRole('button', { name: 'Generate recurring tasks' }).click();
  await expect(page.getByRole('row', { name: /Daily lobby sweep/ })).toHaveCount(1);
  expect(backend.table('tasks').filter((x) => x.title === 'Daily lobby sweep')).toHaveLength(1);
});

test('a failure while loading task details is shown, not rendered as an empty checklist', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('task_checklist_items', { method: 'GET', status: 500, message: 'database unavailable' });
  await page.goto('/tasks');
  await page.getByRole('button', { name: /Clean ground-floor washrooms/ }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toHaveText('Failed to load the task details.');
});

test('employees cannot open Task Management', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/tasks/management');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
