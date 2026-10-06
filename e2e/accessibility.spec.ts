import type { Page } from '@playwright/test';
import { test, expect, expectNoSeriousViolations } from './utils/test';
import type { SignInAs } from './utils/sebetsaFixtures';

/**
 * Accessibility baseline: axe-core over every page a role can reach through its
 * own navigation (light and dark), plus the keyboard behaviour axe cannot see.
 *
 * Automated scanning catches only a subset of WCAG issues (labels, contrast,
 * landmark/role misuse, unlabelled controls). Passing this is a floor, not a
 * certification — it says nothing about screen-reader phrasing or reading order.
 * Every rule gates, including colour contrast.
 */

async function navigationHrefs(page: Page): Promise<string[]> {
  await page.goto('/dashboard');
  await expect(page.getByRole('main')).toBeVisible();
  const hrefs = await page.getByRole('navigation').getByRole('link').evaluateAll((links) => links.map((a) => (a as HTMLAnchorElement).getAttribute('href') ?? ''));
  return [...new Set(hrefs.filter((h) => h.startsWith('/')))];
}

test('the sign-in page has no serious accessibility violations', async ({ page, app }) => {
  await app.open('employee', { signedIn: false });
  await page.goto('/login');
  await expect(page.getByRole('heading', { name: 'Sign in to your account' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

const SWEEP: SignInAs[] = ['organization_administrator', 'operations_manager', 'regional_manager', 'site_manager', 'supervisor', 'hr_user', 'employee', 'client_user'];

for (const role of SWEEP) {
  test(`${role}: every page in their navigation passes axe (light)`, async ({ page, app }) => {
    test.setTimeout(240_000);
    await app.open(role);
    const hrefs = await navigationHrefs(page);
    for (const href of hrefs) {
      await page.goto(href);
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('main'), `${href} renders a main landmark`).toBeVisible();
      await expectNoSeriousViolations(page);
    }
  });
}

for (const role of ['organization_administrator', 'employee'] as const) {
  test(`${role}: every page in their navigation passes axe (dark)`, async ({ page, app }) => {
    test.setTimeout(240_000);
    await page.emulateMedia({ colorScheme: 'dark' });
    await app.open(role);
    const hrefs = await navigationHrefs(page);
    for (const href of hrefs) {
      await page.goto(href);
      await page.waitForLoadState('networkidle');
      await expectNoSeriousViolations(page);
    }
  });
}

test('a modal takes focus, keeps Tab inside, closes on Escape and returns focus to its trigger', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/leave');
  const trigger = page.getByRole('button', { name: 'Request leave' });
  await trigger.focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAttribute('aria-modal', 'true');
  await expect.poll(() => dialog.evaluate((el) => el.contains(document.activeElement))).toBe(true);

  for (let i = 0; i < 25; i += 1) {
    await page.keyboard.press('Tab');
    expect(await dialog.evaluate((el) => el.contains(document.activeElement)), `Tab #${i + 1} stayed inside the dialog`).toBe(true);
  }
  for (let i = 0; i < 25; i += 1) {
    await page.keyboard.press('Shift+Tab');
    expect(await dialog.evaluate((el) => el.contains(document.activeElement)), `Shift+Tab #${i + 1} stayed inside the dialog`).toBe(true);
  }

  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(trigger).toBeFocused();
});

test('form errors are announced and tied to their fields', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/leave');
  await page.getByRole('button', { name: 'Request leave' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: 'Submit request' }).click();
  // Select errors are announced through role=alert; text fields are also programmatically tied.
  await expect(dialog.getByRole('alert').filter({ hasText: 'Leave type is required' })).toBeVisible();
  const start = dialog.getByLabel('Start date');
  await expect(start).toHaveAttribute('aria-invalid', 'true');
  const describedBy = await start.getAttribute('aria-describedby');
  expect(describedBy).toBeTruthy();
  await expect(page.locator(`[id="${describedBy}"]`)).toContainText('Start date is required');
});

test('every page has exactly one h1 and the document has a language and title', async ({ page, app }) => {
  await app.open('operations_manager');
  for (const href of ['/dashboard', '/leave/management', '/tasks/management', '/incidents', '/reports']) {
    await page.goto(href);
    await expect(page.getByRole('main')).toBeVisible();
    expect(await page.locator('h1').count(), `${href} h1 count`).toBe(1);
    expect(await page.locator('html').getAttribute('lang')).toBeTruthy();
    expect((await page.title()).trim().length).toBeGreaterThan(0);
  }
});
