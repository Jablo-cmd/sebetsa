import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('shows a friendly notice when the signed-in user has no profile row', async ({ page, app }) => {
  await app.open('employee', { customize: (t) => (t.profiles = t.profiles.filter((p) => p.id !== PERSONAS.employee.profileId)) });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Profile not found' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText("couldn't find a profile");
});

test('shows a friendly notice when a non-platform role has no organisation assigned', async ({ page, app }) => {
  await app.open('employee', {
    customize: (t) => {
      const profile = t.profiles.find((p) => p.id === PERSONAS.employee.profileId);
      if (profile) profile.tenant_id = null;
    },
  });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'No organization assigned' })).toBeVisible();
});

test('shows a friendly notice when the assigned organisation is inactive', async ({ page, app }) => {
  await app.open('employee', {
    customize: (t) => {
      const org = t.organizations.find((o) => o.id === ID.org);
      if (org) org.status = 'inactive';
    },
  });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Organization inactive' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Brightway Facilities (Demo)');
});

test('blocks a deactivated account from the workspace', async ({ page, app }) => {
  await app.open('employee', {
    customize: (t) => {
      const profile = t.profiles.find((p) => p.id === PERSONAS.employee.profileId);
      if (profile) profile.status = 'inactive';
    },
  });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Account deactivated' })).toBeVisible();
  await expect(page.getByRole('navigation')).toHaveCount(0);
});

test('a profile load failure is reported, never rendered as an empty workspace', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('profiles', { method: 'GET', status: 500, message: 'database unavailable' });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Something went wrong' })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Welcome/ })).toHaveCount(0);
});

test('a platform administrator with no organisation reaches the dashboard and is asked to pick one', async ({ page, app }) => {
  await app.open('platform_administrator');
  await page.goto('/');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
  await expect(page.getByRole('heading', { name: 'Welcome back, Pat' })).toBeVisible();
  await expect(page.getByRole('main').getByText('platform administrator', { exact: true })).toBeVisible();
});
