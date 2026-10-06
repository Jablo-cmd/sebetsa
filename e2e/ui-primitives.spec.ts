import { test, expect } from './utils/test';

test('the account dropdown opens, closes on Escape, and closes on an outside click', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/dashboard');
  await page.getByRole('button', { name: /Omar Mokoena/ }).click();
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toHaveCount(0);

  await page.getByRole('button', { name: /Omar Mokoena/ }).click();
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
  await page.mouse.click(10, 10);
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toHaveCount(0);
});

test('the account menu is keyboard operable and returns focus to its trigger', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/dashboard');
  const trigger = page.getByRole('button', { name: /Omar Mokoena/ });
  await trigger.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toHaveCount(0);
  await expect(trigger).toBeFocused();
});
