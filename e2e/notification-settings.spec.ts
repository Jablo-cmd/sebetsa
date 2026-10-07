import { test, expect, expectNoSeriousViolations } from './utils/test';
import { PERSONAS } from './utils/sebetsaFixtures';

test('defaults are all external channels off; saving persists the choices for the signed-in user only', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/notifications/settings');
  await expect(page.getByRole('heading', { name: 'Notification preferences' })).toBeVisible();
  for (const channel of ['Email', 'SMS', 'WhatsApp']) await expect(page.getByLabel(channel)).not.toBeChecked();
  await expectNoSeriousViolations(page);

  await page.getByLabel('Email').click();
  await page.getByLabel('WhatsApp').click();
  await page.getByLabel('From', { exact: true }).fill('21:00');
  await page.getByLabel('To', { exact: true }).fill('06:30');
  await page.getByRole('button', { name: 'Save preferences' }).click();
  await expect(page.getByText('Notification preferences saved.')).toBeVisible();

  const saved = backend.find('notification_preferences', { profile_id: PERSONAS.employee.profileId });
  expect(saved).toMatchObject({ email_enabled: true, sms_enabled: false, whatsapp_enabled: true, quiet_hours_start: '21:00', quiet_hours_end: '06:30' });
  expect(backend.table('notification_preferences').filter((p) => p.profile_id !== PERSONAS.employee.profileId)).toHaveLength(0);
});

test('saved preferences are shown again on the next visit, and quiet hours can be cleared', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) =>
      t.notification_preferences.push({ profile_id: PERSONAS.employee.profileId, email_enabled: true, sms_enabled: true, whatsapp_enabled: false, quiet_hours_start: '22:00:00', quiet_hours_end: '05:00:00', updated_at: '2026-01-05T08:00:00.000Z' }),
  });
  await page.goto('/notifications/settings');
  await expect(page.getByLabel('Email')).toBeChecked();
  await expect(page.getByLabel('SMS')).toBeChecked();
  await expect(page.getByLabel('WhatsApp')).not.toBeChecked();
  await expect(page.getByLabel('From', { exact: true })).toHaveValue('22:00');
  await page.getByLabel('From', { exact: true }).fill('');
  await page.getByLabel('To', { exact: true }).fill('');
  await page.getByRole('button', { name: 'Save preferences' }).click();
  await expect(page.getByText('Notification preferences saved.')).toBeVisible();
  expect(backend.find('notification_preferences', { profile_id: PERSONAS.employee.profileId })).toMatchObject({ quiet_hours_start: null, quiet_hours_end: null });
  expect(backend.table('notification_preferences')).toHaveLength(1);
});

test('failures to load or save are shown', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('notification_preferences', { method: 'GET', times: 1 });
  await page.goto('/notifications/settings');
  await expect(page.getByText('Failed to load your preferences.')).toBeVisible();

  await page.reload();
  await expect(page.getByRole('button', { name: 'Save preferences' })).toBeVisible();
  backend.fault('notification_preferences', { method: 'POST', times: 1 });
  await page.getByLabel('SMS').click();
  await page.getByRole('button', { name: 'Save preferences' }).click();
  await expect(page.getByText('Failed to save.')).toBeVisible();
  expect(backend.table('notification_preferences')).toHaveLength(0);
});

test('every internal role can reach their own preferences', async ({ page, app }) => {
  for (const role of ['organization_administrator', 'supervisor', 'hr_user', 'client_user'] as const) {
    await app.open(role);
    await page.goto('/notifications/settings');
    await expect(page.getByRole('heading', { name: 'Notification preferences' })).toBeVisible();
  }
});

test('quiet hours are saved with the chosen time zone, and "organisation time zone" clears it', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/notifications/settings');
  await expect(page.getByLabel('Time zone')).toHaveValue('');

  await page.getByLabel('From', { exact: true }).fill('22:00');
  await page.getByLabel('To', { exact: true }).fill('06:00');
  await page.getByLabel('Time zone').selectOption('Africa/Maputo');
  await page.getByRole('button', { name: 'Save preferences' }).click();
  await expect(page.getByText('Notification preferences saved.')).toBeVisible();
  expect(backend.find('notification_preferences', { profile_id: PERSONAS.employee.profileId })).toMatchObject({ time_zone: 'Africa/Maputo' });

  await page.reload();
  await expect(page.getByLabel('Time zone')).toHaveValue('Africa/Maputo');
  await page.getByLabel('Time zone').selectOption('');
  await page.getByRole('button', { name: 'Save preferences' }).click();
  await expect(page.getByText('Notification preferences saved.')).toBeVisible();
  expect(backend.find('notification_preferences', { profile_id: PERSONAS.employee.profileId })).toMatchObject({ time_zone: null });
});
