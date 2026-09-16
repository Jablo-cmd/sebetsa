import { test, expect } from '@playwright/test';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow } from './utils/sebetsaData';

test('the account dropdown opens, closes on Escape, and closes on an outside click', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee', first_name: 'Ada', last_name: 'Employee' }) });

  await page.goto('/dashboard');
  await page.getByRole('button', { name: /Ada Employee/ }).click();
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toHaveCount(0);

  await page.getByRole('button', { name: /Ada Employee/ }).click();
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
  await page.mouse.click(10, 10);
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toHaveCount(0);
});
