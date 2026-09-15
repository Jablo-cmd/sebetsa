import { test, expect } from '@playwright/test';
import { fulfillJson } from './utils/mockAuth';
import { seedSebetsaSession, buildSebetsaUser } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow } from './utils/sebetsaData';

const USER_ID = buildSebetsaUser().id;

function buildNotificationRow(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'notification-1',
    tenant_id: '22222222-2222-2222-2222-222222222222',
    recipient_profile_id: USER_ID,
    type: 'leave_approved',
    title: 'Leave request approved',
    body: 'Your leave request for 3 days has been approved.',
    related_entity_table: 'leave_requests',
    related_entity_id: 'leave-request-1',
    link_path: '/leave',
    read_at: null,
    created_at: '2026-08-01T09:00:00Z',
    ...overrides,
  };
}

test('the header bell shows an unread badge and links to the notifications list', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });
  await page.route('**/rest/v1/notifications*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, [buildNotificationRow(), buildNotificationRow({ id: 'notification-2', title: 'Second one', read_at: '2026-08-02T09:00:00Z' })]);
  });

  await page.goto('/dashboard');
  const bell = page.getByRole('link', { name: /Notifications, 1 unread/ });
  await expect(bell).toBeVisible();

  await bell.click();
  await expect(page.getByRole('heading', { name: 'Notifications' })).toBeVisible();
  await expect(page.getByText('Leave request approved')).toBeVisible();
  await expect(page.getByText('Second one')).toBeVisible();
});

test('opening an unread notification marks it read and navigates to its link_path', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  let markedRead = false;
  await page.route('**/rest/v1/notifications*', async (route) => {
    if (route.request().method() === 'PATCH') {
      markedRead = true;
      await fulfillJson(route, buildNotificationRow({ read_at: '2026-08-03T09:00:00Z' }));
      return;
    }
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, markedRead ? [buildNotificationRow({ read_at: '2026-08-03T09:00:00Z' })] : [buildNotificationRow()]);
  });

  await page.goto('/notifications');
  await expect(page.getByRole('heading', { name: 'Notifications' })).toBeVisible();
  await page.getByText('Leave request approved').click();

  await expect(page).toHaveURL('http://localhost:5173/leave');
});

test('"Mark all as read" clears every unread notification in one action', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  let markedAll = false;
  await page.route('**/rest/v1/notifications*', async (route) => {
    if (route.request().method() === 'PATCH') {
      markedAll = true;
      await fulfillJson(route, []);
      return;
    }
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(
      route,
      markedAll
        ? [
            buildNotificationRow({ read_at: '2026-08-03T09:00:00Z' }),
            buildNotificationRow({ id: 'notification-2', title: 'Second one', read_at: '2026-08-03T09:00:00Z' }),
          ]
        : [buildNotificationRow(), buildNotificationRow({ id: 'notification-2', title: 'Second one' })],
    );
  });

  await page.goto('/notifications');
  await expect(page.getByRole('button', { name: 'Mark all as read' })).toBeVisible();
  await page.getByRole('button', { name: 'Mark all as read' }).click();

  // markAllRead() is an async click handler — click() only waits for the
  // DOM event to dispatch, not for the PATCH request it kicks off. Assert
  // on the retrying UI expectation first (which only passes once the
  // resulting re-render has actually happened) so markedAll is read after
  // the real async work is guaranteed done, not raced against it.
  await expect(page.getByRole('button', { name: 'Mark all as read' })).toHaveCount(0);
  expect(markedAll).toBe(true);
});

test('a user with no notifications sees an empty state, not an error', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });
  await page.route('**/rest/v1/notifications*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, []);
  });

  await page.goto('/dashboard');
  await expect(page.getByRole('link', { name: 'Notifications', exact: true }).first()).toBeVisible();
  await expect(page.getByText(/\d\+? unread/)).toHaveCount(0);

  await page.goto('/notifications');
  await expect(page.getByText('Nothing here yet.')).toBeVisible();
});
