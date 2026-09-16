import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  installStorageUploadMock,
  installStorageSignedUrlMock,
  buildProfileRow,
  buildEmployeeRow,
  buildEmployeeDocumentRow,
  fulfillJson,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

test('employee can upload and view their own document', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    employeeDocuments: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'create_document_upload_slot') {
        const created = buildEmployeeDocumentRow({ file_name: payload.p_file_name, mime_type: payload.p_mime_type, file_size_bytes: payload.p_file_size_bytes });
        state.employeeDocuments = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      return false;
    },
  });
  await installStorageUploadMock(page, 'employee-documents');
  await installStorageSignedUrlMock(page, 'employee-documents');

  await page.goto('/documents');
  await expect(page.getByRole('heading', { name: 'My Documents' })).toBeVisible();
  await expect(page.getByText('No documents yet.')).toBeVisible();

  await page.setInputFiles('#document-file', {
    name: 'first-aid.pdf',
    mimeType: 'application/pdf',
    buffer: Buffer.from('%PDF-1.4 mock content'),
  });
  await page.getByRole('button', { name: 'Upload' }).click();

  await expect(page.getByText('first-aid.pdf')).toBeVisible();
});

test('operations_manager can search for an employee, upload on their behalf, and verify a document', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    employeeDocuments: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'verify_document') {
        const decided = { ...(state.employeeDocuments?.[0] ?? buildEmployeeDocumentRow()), status: 'verified', verified_by: '11111111-1111-1111-1111-111111111111' };
        state.employeeDocuments = [decided];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(decided) });
        return true;
      }
      return false;
    },
  });

  // Employee-candidate search returns an array (limit-only query) —
  // distinct from the single-object /employees mock installSebetsaMocks
  // installs by default, so this override must be registered after it.
  await page.route('**/rest/v1/employees*', async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() !== 'GET' || !url.searchParams.has('limit')) return route.fallback();
    await fulfillJson(route, [{ id: 'employee-1', first_name: 'Karabo', last_name: 'Mokoena' }]);
  });

  await page.goto('/documents/manage');
  await expect(page.getByRole('heading', { name: 'Employee Documents' })).toBeVisible();

  await page.getByLabel('Employee').fill('Karabo');
  await page.getByRole('button', { name: 'Karabo Mokoena' }).click();

  state.employeeDocuments = [buildEmployeeDocumentRow()];
  await page.reload();
  await page.getByLabel('Employee').fill('Karabo');
  await page.getByRole('button', { name: 'Karabo Mokoena' }).click();

  await expect(page.getByText('first-aid.pdf')).toBeVisible();
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByText('Verified')).toBeVisible();
});

test('an unsupported file type is rejected before any upload request is made', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow(), employeeDocuments: [] });

  let uploadAttempted = false;
  await page.route('**/storage/v1/object/employee-documents/**', async (route) => {
    uploadAttempted = true;
    await route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
  });

  await page.goto('/documents');
  await page.setInputFiles('#document-file', {
    name: 'malware.exe',
    mimeType: 'application/x-msdownload',
    buffer: Buffer.from('not a real document'),
  });

  await expect(page.getByText('Only PDF, JPEG, or PNG files are accepted.')).toBeVisible();
  expect(uploadAttempted).toBe(false);
});

test('an oversized file is rejected before any upload request is made', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow(), employeeDocuments: [] });

  let uploadAttempted = false;
  await page.route('**/storage/v1/object/employee-documents/**', async (route) => {
    uploadAttempted = true;
    await route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
  });

  await page.goto('/documents');
  await page.setInputFiles('#document-file', {
    name: 'huge.pdf',
    mimeType: 'application/pdf',
    buffer: Buffer.alloc(11 * 1024 * 1024, 'x'),
  });

  await expect(page.getByText('Maximum file size is 10MB.')).toBeVisible();
  expect(uploadAttempted).toBe(false);
});

test('a self-service user without a linked employee record sees a clear message instead of the upload form', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: null });

  await page.goto('/documents');
  await expect(page.getByText('No employee record is linked to your account.')).toBeVisible();
  await expect(page.getByLabel('Document type')).toHaveCount(0);
});

test('opening a document resolves a fresh signed URL rather than a stored public link', async ({ page, context }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    employeeDocuments: [buildEmployeeDocumentRow({ id: 'document-1' })],
  });
  await installStorageSignedUrlMock(page, 'employee-documents');
  // The resolved signed URL opens in a new tab via window.open, whose own
  // navigation request page.route() never sees — only a context-wide route
  // reaches it too.
  await context.route('**/object/sign/employee-documents/mock-path*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'text/plain', body: 'mock signed file content' });
  });

  await page.goto('/documents');
  const [popup] = await Promise.all([page.waitForEvent('popup'), page.getByRole('button', { name: 'View' }).click()]);
  await popup.waitForLoadState('load');
  expect(popup.url()).toContain('/object/sign/employee-documents/mock-path');
  expect(popup.url()).toContain('token=mock-token');
  await popup.close();
});

test('an employee is blocked from Employee Documents', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/documents/manage');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('My Documents has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow(), employeeDocuments: [buildEmployeeDocumentRow()] });
  await page.goto('/documents');
  await expect(page.getByRole('heading', { name: 'My Documents' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Employee Documents has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'operations_manager' }) });
  await page.goto('/documents/manage');
  await expect(page.getByRole('heading', { name: 'Employee Documents' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
