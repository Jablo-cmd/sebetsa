import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, TODAY } from './utils/sebetsaFixtures';

import type { Page } from '@playwright/test';

/** The value shown on a StatCard (the number under its label). */
const stat = (page: Page, label: string) => page.getByText(label, { exact: true }).locator('xpath=following-sibling::p');

const attendanceToday = (id: number, status: string, employeeId: string) => ({
  id: `00000000-0000-4000-8000-0028${String(id).padStart(8, '0')}`,
  tenant_id: ID.org,
  shift_id: null,
  site_id: ID.siteTowerA,
  employee_id: employeeId,
  status,
  clock_in_at: null,
  clock_out_at: null,
  recorded_by: null,
  notes: null,
  late_minutes: null,
  early_departure_minutes: null,
  worked_minutes: null,
  overtime_minutes: null,
  created_at: `${TODAY}T05:00:00.000Z`,
  updated_at: `${TODAY}T05:00:00.000Z`,
});

test('the overview reports assigned, scheduled, open-task and staffing figures for the first site', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/site-operations');
  await expect(page.getByRole('heading', { name: 'Site Operations' })).toBeVisible();
  await expect(page.getByLabel('Site')).toHaveValue(ID.siteTowerA);

  await expect(stat(page, 'Assigned')).toHaveText('3');
  await expect(stat(page, 'Scheduled today')).toHaveText('2');
  await expect(stat(page, 'Open tasks')).toHaveText('2');
  await expect(stat(page, 'Present')).toHaveText('0');
  await expect(stat(page, 'Required')).toHaveText('3');
  // Nobody has been marked present yet, so the whole requirement is a shortage.
  await expect(stat(page, 'Shortage')).toHaveText('3');
  await expectNoSeriousViolations(page);
});

test('today\'s attendance is counted by status and reduces the shortage', async ({ page, app }) => {
  await app.open('operations_manager', {
    customize: (t) => {
      t.attendance_records.push(
        attendanceToday(1, 'present', ID.siteTowerA),
        attendanceToday(2, 'present', ID.siteTowerA),
        attendanceToday(3, 'late', ID.siteTowerA),
        attendanceToday(4, 'absent', ID.siteTowerA),
      );
      // Yesterday's records must not leak into today's figures.
      t.attendance_records.push({ ...attendanceToday(5, 'present', ID.siteTowerA), created_at: '2026-09-20T05:00:00.000Z' });
    },
  });
  await page.goto('/site-operations');
  await expect(stat(page, 'Present')).toHaveText('2');
  await expect(stat(page, 'Late')).toHaveText('1');
  await expect(stat(page, 'Absent')).toHaveText('1');
  await expect(stat(page, 'Shortage')).toHaveText('1');
});

test('switching site reloads the figures for that site', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/site-operations');
  await expect(stat(page, 'Assigned')).toHaveText('3');
  await page.getByLabel('Site').selectOption(ID.siteAtrium);
  await expect(stat(page, 'Assigned')).toHaveText('0');
  await expect(stat(page, 'Open tasks')).toHaveText('0');
  // No requirement is configured for this site, so there is no shortage figure.
  await expect(page.getByText('Required', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Shortage', { exact: true })).toHaveCount(0);
});

test('a manager adds a staffing requirement, then updates it by reusing the label', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/site-operations');
  const save = page.getByRole('button', { name: 'Save' });
  await expect(save).toBeDisabled();

  await page.getByLabel('Label').fill('Night guards');
  await page.getByLabel('Required count').fill('2');
  await save.click();
  await expect(stat(page, 'Required')).toHaveText('5');
  await expect(page.getByText('Night guards')).toBeVisible();
  await expect(page.getByLabel('Label')).toHaveValue('');
  expect(backend.find('site_staffing_requirements', { label: 'Night guards' })).toMatchObject({ required_count: 2, site_id: ID.siteTowerA });

  // Same label again updates in place rather than creating a duplicate.
  await page.getByLabel('Label').fill('Day cleaners');
  await page.getByLabel('Required count').fill('4');
  await save.click();
  await expect(stat(page, 'Required')).toHaveText('6');
  expect(backend.table('site_staffing_requirements').filter((r) => r.label === 'Day cleaners')).toHaveLength(1);
  expect(backend.find('site_staffing_requirements', { label: 'Day cleaners' })).toMatchObject({ required_count: 4 });
});

test('a failed save keeps the form and shows the error', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/site-operations');
  backend.fault('site_staffing_requirements', { method: 'POST', times: 1 });
  await page.getByLabel('Label').fill('Reception');
  await page.getByLabel('Required count').fill('1');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Failed to save the staffing requirement.')).toBeVisible();
  await expect(page.getByLabel('Label')).toHaveValue('Reception');
  expect(backend.table('site_staffing_requirements')).toHaveLength(1);
});

test('a failed overview load is reported instead of showing zeros', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  backend.fault('shifts');
  await page.goto('/site-operations');
  await expect(page.getByText('Failed to load site workforce overview.')).toBeVisible();
  await expect(page.getByText('Assigned', { exact: true })).toHaveCount(0);
});

test('HR can view the overview but not edit staffing requirements', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto('/site-operations');
  await expect(stat(page, 'Assigned')).toHaveText('3');
  await expect(page.getByRole('heading', { name: 'Staffing requirements' })).toHaveCount(0);
});

test('employees and clients are redirected away from Site Operations', async ({ page, app }) => {
  for (const role of ['employee', 'client_user'] as const) {
    await app.open(role);
    await page.goto('/site-operations');
    await expect(page).not.toHaveURL(/site-operations/);
  }
});
