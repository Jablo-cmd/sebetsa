import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

function notification(id: string, recipient: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    tenant_id: ID.org,
    recipient_profile_id: recipient,
    type: 'task_assigned',
    title: 'Task assigned',
    body: 'Clean ground-floor washrooms has been assigned to you.',
    related_entity_table: 'tasks',
    related_entity_id: ID.taskWashrooms,
    link_path: '/tasks',
    email_status: 'not_sent',
    read_at: null,
    created_at: '2026-09-20T09:00:00.000Z',
    ...overrides,
  };
}

test('the header bell shows an unread badge and links to the notifications list', async ({ page, app }) => {
  await app.open('employee', {
    customize: (t) => t.notifications.push(notification('00000000-0000-4000-8000-00ff00000001', PERSONAS.employee.profileId), notification('00000000-0000-4000-8000-00ff00000002', PERSONAS.employee.profileId, { title: 'Second one', read_at: '2026-09-20T10:00:00.000Z' })),
  });
  await page.goto('/dashboard');
  const bell = page.getByRole('banner').getByRole('link', { name: /Notifications/ });
  await expect(bell).toHaveAccessibleName('Notifications, 2 unread');

  await bell.click();
  await expect(page.getByRole('heading', { name: 'Notifications' })).toBeVisible();
  await expect(page.getByText('Task assigned')).toBeVisible();
  await expect(page.getByText('Second one')).toBeVisible();
});

test("a user only ever sees their own notifications, never another person's", async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/notifications');
  await expect(page.getByText('Welcome to Sebetsa')).toHaveCount(1);
});

test('opening an unread notification marks it read in the backend and navigates to its link_path', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => t.notifications.push(notification('00000000-0000-4000-8000-00ff00000001', PERSONAS.employee.profileId)),
  });
  await page.goto('/notifications');
  await page.getByText('Task assigned').click();

  await expect(page).toHaveURL('http://localhost:5173/tasks');
  expect(backend.find('notifications', { id: '00000000-0000-4000-8000-00ff00000001' }).read_at).not.toBeNull();
  await expect(page.getByRole('banner').getByRole('link', { name: /Notifications/ })).toHaveAccessibleName(/Notifications/);
});

test('"Mark all as read" clears only the signed-in user\'s unread notifications', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => t.notifications.push(notification('00000000-0000-4000-8000-00ff00000001', PERSONAS.employee.profileId), notification('00000000-0000-4000-8000-00ff00000002', PERSONAS.employee.profileId, { title: 'Second one' })),
  });
  await page.goto('/notifications');
  await page.getByRole('button', { name: 'Mark all as read' }).click();

  await expect(page.getByRole('button', { name: 'Mark all as read' })).toHaveCount(0);
  const mine = backend.table('notifications').filter((n) => n.recipient_profile_id === PERSONAS.employee.profileId);
  expect(mine.every((n) => n.read_at !== null)).toBe(true);
  const others = backend.table('notifications').filter((n) => n.recipient_profile_id !== PERSONAS.employee.profileId);
  expect(others.length).toBeGreaterThan(0);
  expect(others.every((n) => n.read_at === null)).toBe(true);
});

test('a user with no notifications sees an empty state, not an error', async ({ page, app }) => {
  await app.open('employee', { customize: (t) => (t.notifications = []) });
  await page.goto('/dashboard');
  await expect(page.getByRole('banner').getByRole('link', { name: 'Notifications', exact: true })).toBeVisible();
  await expect(page.getByText(/\d\+? unread/)).toHaveCount(0);

  await page.goto('/notifications');
  await expect(page.getByText('Nothing here yet.')).toBeVisible();
  await expect(page.getByRole('alert')).toHaveCount(0);
});

test('a failed mark-as-read is surfaced and the notification stays unread', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('notifications', { method: 'PATCH', status: 500, message: 'write failed' });
  await page.goto('/notifications');
  await page.getByText('Welcome to Sebetsa').click();

  await expect(page.getByRole('alert')).toBeVisible();
  expect(backend.find('notifications', { recipient_profile_id: PERSONAS.employee.profileId }).read_at).toBeNull();
});
