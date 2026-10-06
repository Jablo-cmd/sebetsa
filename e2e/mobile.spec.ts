import type { Page } from '@playwright/test';
import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

/**
 * Phone-viewport coverage (390x844, iPhone 12/13 class): the field-critical
 * workflows (attendance, tasks, leave) and the shell's navigation drawer, plus
 * a sweep proving no page a role can reach forces horizontal page scrolling.
 */
const PHONE_VIEWPORT = { width: 390, height: 844 };

async function expectNoHorizontalOverflow(page: Page, where: string) {
  const overflow = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth }));
  expect(overflow.scroll, `${where} overflows horizontally (${overflow.scroll}px > ${overflow.client}px)`).toBeLessThanOrEqual(overflow.client);
}

async function drawerLinks(page: Page): Promise<string[]> {
  await page.getByRole('button', { name: /menu/i }).click();
  const hrefs = await page.getByRole('navigation').getByRole('link').evaluateAll((links) => links.map((a) => (a as HTMLAnchorElement).getAttribute('href') ?? ''));
  await page.keyboard.press('Escape');
  return [...new Set(hrefs.filter((h) => h.startsWith('/')))];
}

test.describe('phone viewport (390x844)', () => {
  test.use({ viewport: PHONE_VIEWPORT });

  test('the navigation drawer opens, lists the employee\'s modules, navigates and closes', async ({ page, app }) => {
    await app.open('employee');
    await page.goto('/dashboard');
    await page.getByRole('button', { name: /menu/i }).click();
    const drawer = page.getByRole('navigation');
    await expect(drawer.getByRole('link', { name: 'My Leave' })).toBeVisible();
    await expect(drawer.getByRole('link', { name: 'My Tasks' })).toBeVisible();
    await expect(drawer.getByRole('link', { name: 'My Attendance' })).toBeVisible();
    // Manager-only modules are not offered at all.
    await expect(drawer.getByRole('link', { name: 'Task Management' })).toHaveCount(0);

    await drawer.getByRole('link', { name: 'My Attendance' }).click();
    await expect(page).toHaveURL(/\/attendance\/mine/);
    await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
  });

  test('an employee clocks in with a thumb-sized button, at their assigned site', async ({ page, app }) => {
    const backend = await app.open('employee');
    await page.goto('/attendance/mine');
    await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
    const clockIn = page.getByRole('button', { name: 'Clock in' });
    await expect(clockIn).toBeVisible();
    const box = await clockIn.boundingBox();
    expect(box?.height ?? 0, 'touch target height').toBeGreaterThanOrEqual(40);
    expect(box?.width ?? 0, 'touch target width').toBeGreaterThanOrEqual(40);

    await clockIn.click();
    await expect(page.getByText(/Clocked in at/)).toBeVisible();
    const record = backend.table('attendance_records').find((r) => r.employee_id === PERSONAS.employee.employeeId && r.clock_in_at);
    expect(record, 'a clock-in record was written for the signed-in employee').toBeTruthy();
    await expect(page.getByRole('button', { name: 'Clock out' })).toBeVisible();
    await expectNoHorizontalOverflow(page, 'My Attendance');
  });

  test('an employee opens a task and sees its checklist on a phone', async ({ page, app }) => {
    await app.open('employee');
    await page.goto('/tasks');
    await expect(page.getByRole('heading', { name: 'My Tasks' })).toBeVisible();
    await page.getByText('Clean ground-floor washrooms').click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Clean ground-floor washrooms' })).toBeVisible();
    await expect(dialog.getByText('Disinfect fixtures')).toBeVisible();
    const box = await dialog.boundingBox();
    expect(box?.width ?? 0).toBeLessThanOrEqual(PHONE_VIEWPORT.width);
    await dialog.getByLabel('Disinfect fixtures').click();
    await expect(dialog.getByLabel('Disinfect fixtures')).toBeChecked();
  });

  test('the leave request form fits the screen and submits', async ({ page, app }) => {
    const backend = await app.open('employee');
    await page.goto('/leave');
    await page.getByRole('button', { name: 'Request leave' }).click();
    const modal = page.getByRole('dialog');
    await expect(modal.getByRole('heading', { name: 'Request leave' })).toBeVisible();
    const box = await modal.boundingBox();
    expect(box?.width ?? 0).toBeLessThanOrEqual(PHONE_VIEWPORT.width);
    expect(box?.x ?? -1).toBeGreaterThanOrEqual(0);

    await modal.getByLabel('Leave type').selectOption({ label: 'Annual' });
    await modal.getByLabel('Start date').fill('2026-10-12');
    await modal.getByLabel('End date').fill('2026-10-12');
    // The submit button must be reachable without leaving the dialog.
    await modal.getByRole('button', { name: 'Submit request' }).scrollIntoViewIfNeeded();
    await modal.getByRole('button', { name: 'Submit request' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect(backend.table('leave_requests').filter((r) => r.employee_id === PERSONAS.employee.employeeId)).toHaveLength(1);
  });

  test('a supervisor marks the roster using the stacked mobile layout', async ({ page, app }) => {
    await app.open('supervisor');
    await page.goto('/attendance');
    await expect(page.getByRole('heading', { name: 'Attendance' })).toBeVisible();
    // The desktop table is hidden; the card layout is what a phone user sees.
    await expect(page.getByRole('table')).toBeHidden();
    await expect(page.locator('p', { hasText: 'Thabo Nkosi' }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'Late' }).first()).toBeVisible();
    await expectNoHorizontalOverflow(page, 'Attendance register');
  });

  test('an employee is still blocked from manager-only pages at phone width', async ({ page, app }) => {
    await app.open('employee');
    await page.goto('/tasks/management');
    await expect(page).toHaveURL(/\/dashboard$/);
  });

  for (const role of ['employee', 'supervisor', 'site_manager', 'operations_manager', 'hr_user'] as const) {
    test(`${role}: every page in their navigation fits a phone without horizontal scrolling`, async ({ page, app }) => {
      test.setTimeout(120_000);
      await app.open(role);
      await page.goto('/dashboard');
      const links = await drawerLinks(page);
      expect(links.length, 'the role has navigation').toBeGreaterThan(2);
      for (const href of links) {
        await page.goto(href);
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('main')).toBeVisible();
        await expectNoHorizontalOverflow(page, `${role} ${href}`);
      }
    });
  }

  test('key pages carry no serious accessibility violations at phone width', async ({ page, app }) => {
    await app.open('employee');
    for (const href of ['/attendance/mine', '/tasks', '/leave', '/dashboard']) {
      await page.goto(href);
      await page.waitForLoadState('networkidle');
      await expectNoSeriousViolations(page);
    }
    void ID;
  });
});
