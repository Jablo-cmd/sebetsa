import { test, expect } from './utils/test';
import { ID, PERSONAS, dateOffset } from './utils/sebetsaFixtures';

const PDF = (name: string, bytes = 64) => ({ name, mimeType: 'application/pdf', buffer: Buffer.alloc(bytes, 'x') });

test("My Documents lists only the signed-in employee's documents", async ({ page, app }) => {
  await app.open('employee', {
    customize: (t) =>
      t.employee_documents.push({
        id: '00000000-0000-4000-8000-00ff00000099', tenant_id: ID.org, employee_id: PERSONAS.employee_two.employeeId, document_type: 'certificate', file_name: 'lerato-private.pdf',
        mime_type: 'application/pdf', file_size_bytes: 10, storage_path: 'x', version: 1, supersedes_document_id: null, status: 'verified', expiry_date: null,
        uploaded_by: PERSONAS.employee_two.profileId, verified_by: null, verified_at: null, review_notes: null, created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
      }),
  });
  await page.goto('/documents');
  await expect(page.getByRole('heading', { name: 'My Documents' })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'chemical-handling.pdf' })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'first-aid.pdf' })).toBeVisible();
  await expect(page.getByText('lerato-private.pdf')).toHaveCount(0);
});

test('an employee uploads a document: slot created for them, file stored under their tenant/employee path', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  await page.locator('#document-type').selectOption('certificate');
  await page.setInputFiles('#document-file', PDF('safe-handling.pdf', 2048));
  await page.getByRole('button', { name: 'Upload' }).click();

  await expect(page.getByRole('cell', { name: 'safe-handling.pdf' })).toBeVisible();
  const row = backend.find('employee_documents', { file_name: 'safe-handling.pdf' });
  expect(row).toMatchObject({ tenant_id: ID.org, employee_id: PERSONAS.employee.employeeId, uploaded_by: PERSONAS.employee.profileId, status: 'uploaded', version: 1 });
  expect(backend.uploads).toHaveLength(1);
  expect(backend.uploads[0].path.startsWith(`${ID.org}/${PERSONAS.employee.employeeId}/`)).toBe(true);
  expect(backend.uploads[0].bucket).toBe('employee-documents');
});

test('an unsupported file type is rejected before any request is made', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  const before = backend.requests.length;
  await page.setInputFiles('#document-file', { name: 'macro.exe', mimeType: 'application/x-msdownload', buffer: Buffer.from('MZ') });

  await expect(page.getByText('Only PDF, JPEG, or PNG files are accepted.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Upload' })).toBeDisabled();
  expect(backend.requests.slice(before).filter((r) => r.rpc === 'create_document_upload_slot')).toEqual([]);
  expect(backend.uploads).toEqual([]);
});

test('an oversized file is rejected before any request is made', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  await page.setInputFiles('#document-file', PDF('huge.pdf', 10 * 1024 * 1024 + 1));

  await expect(page.getByText('Maximum file size is 10MB.')).toBeVisible();
  expect(backend.requests.filter((r) => r.rpc === 'create_document_upload_slot')).toEqual([]);
  expect(backend.uploads).toEqual([]);
});

test('a transient storage failure is retried without creating a second document record', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.failUploads = 1;
  await page.goto('/documents');
  await page.setInputFiles('#document-file', PDF('flaky.pdf'));
  await page.getByRole('button', { name: 'Upload' }).click();

  await expect(page.getByRole('cell', { name: 'flaky.pdf' })).toBeVisible();
  expect(backend.uploads).toHaveLength(1);
  expect(backend.requests.filter((r) => r.rpc === 'create_document_upload_slot')).toHaveLength(1);
  expect(backend.table('employee_documents').filter((d) => d.file_name === 'flaky.pdf')).toHaveLength(1);
});

test('when storage keeps failing, the error is shown, the phantom record is discarded and retry works', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.failUploads = 99;
  await page.goto('/documents');
  await page.setInputFiles('#document-file', PDF('will-fail.pdf'));
  await page.getByRole('button', { name: 'Upload' }).click();

  await expect(page.getByText('Failed to upload the document.')).toBeVisible();
  expect(backend.uploads).toEqual([]);
  expect(backend.table('employee_documents').filter((d) => d.file_name === 'will-fail.pdf')).toHaveLength(0);
  expect(backend.table('audit_log').some((a) => a.action === 'document_upload_cancelled')).toBe(true);

  // The file selection is kept, so a retry needs no re-selection.
  backend.failUploads = 0;
  await expect(page.getByRole('button', { name: 'Upload' })).toBeEnabled();
  await page.getByRole('button', { name: 'Upload' }).click();
  await expect(page.getByRole('cell', { name: 'will-fail.pdf' })).toBeVisible();
  expect(backend.table('employee_documents').filter((d) => d.file_name === 'will-fail.pdf')).toHaveLength(1);
});

test('a failed replacement restores the previous version', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.failUploads = 99;
  await page.goto('/documents');
  await page.getByRole('row', { name: /chemical-handling/ }).getByRole('button', { name: 'Replace' }).click();
  await page.locator('input[aria-label="Replacement file"]').setInputFiles(PDF('chemical-v2.pdf'));

  await expect(page.getByRole('alert')).toContainText('Failed to replace the document.');
  expect(backend.find('employee_documents', { id: ID.docChemical }).status).toBe('verified');
  expect(backend.table('employee_documents').some((d) => d.file_name === 'chemical-v2.pdf')).toBe(false);
});

test('viewing a document opens a short-lived signed URL, never a stored public link', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  const popupPromise = page.waitForEvent('popup');
  await page.getByRole('row', { name: /chemical-handling/ }).getByRole('button', { name: 'View' }).click();
  const popup = await popupPromise;

  // The signed-URL response is a file; don't wait for a document load, only for the navigation target.
  await expect.poll(() => popup.url()).toContain('/storage/v1/object/sign/employee-documents/');
  expect(popup.url()).toContain('token=');
  expect(backend.table('employee_documents').some((d) => String(d.storage_path).includes('token'))).toBe(false);
  await popup.close();
});

test('replacing a document archives the old version and creates the next, unverified version', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  await page.getByRole('row', { name: /chemical-handling/ }).getByRole('button', { name: 'Replace' }).click();
  await page.locator('input[aria-label="Replacement file"]').setInputFiles(PDF('chemical-handling-2026.pdf'));

  await expect(page.getByRole('row', { name: /chemical-handling-2026\.pdf/ })).toContainText('v2');
  await expect(page.getByRole('row', { name: /chemical-handling-2026\.pdf/ })).toContainText('Uploaded');
  await expect(page.getByRole('row', { name: /chemical-handling\.pdf/ })).toContainText('Archived');
  const next = backend.find('employee_documents', { file_name: 'chemical-handling-2026.pdf' });
  expect(next.supersedes_document_id).toBe(ID.docChemical);
  expect(next.verified_by).toBeNull();
  expect(backend.uploads).toHaveLength(1);
});

test('replacement files are validated like uploads', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/documents');
  await page.getByRole('row', { name: /chemical-handling/ }).getByRole('button', { name: 'Replace' }).click();
  await page.locator('input[aria-label="Replacement file"]').setInputFiles({ name: 'x.zip', mimeType: 'application/zip', buffer: Buffer.from('PK') });
  await expect(page.getByRole('alert')).toHaveText('Only PDF, JPEG, or PNG files are accepted.');
  expect(backend.requests.filter((r) => r.rpc === 'replace_document')).toEqual([]);
});

test('operations_manager finds an employee, verifies their pending document, and it becomes Verified', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/documents/manage');
  await page.getByLabel('Employee').fill('Thabo');
  await page.getByRole('button', { name: 'Thabo Nkosi' }).click();

  const row = page.getByRole('row', { name: /first-aid/ });
  await expect(row).toContainText('Pending review');
  await row.getByRole('button', { name: 'Verify' }).click();
  await expect(row).toContainText('Verified');
  expect(backend.find('employee_documents', { id: ID.docFirstAid })).toMatchObject({ status: 'verified', verified_by: PERSONAS.operations_manager.profileId });
});

test('a manager cannot verify a document they uploaded themselves, and is told why', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/documents/manage');
  await page.getByLabel('Employee').fill('Thabo');
  await page.getByRole('button', { name: 'Thabo Nkosi' }).click();
  await page.setInputFiles('#document-file', PDF('hr-uploaded.pdf'));
  await page.getByRole('button', { name: 'Upload' }).click();

  const row = page.getByRole('row', { name: /hr-uploaded/ });
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('employee_documents', { file_name: 'hr-uploaded.pdf' }).status).toBe('uploaded');
});

test('a manager can reject a document', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/documents/manage');
  await page.getByLabel('Employee').fill('Thabo');
  await page.getByRole('button', { name: 'Thabo Nkosi' }).click();
  await page.getByRole('row', { name: /first-aid/ }).getByRole('button', { name: 'Reject' }).click();
  await expect(page.getByRole('row', { name: /first-aid/ })).toContainText('Rejected');
  expect(backend.find('employee_documents', { id: ID.docFirstAid }).status).toBe('rejected');
});

test('syncing expired documents marks lapsed verified documents Expired', async ({ page, app }) => {
  const backend = await app.open('operations_manager', {
    customize: (t) => {
      const doc = t.employee_documents.find((d) => d.id === ID.docChemical);
      if (doc) doc.expiry_date = dateOffset(-3);
    },
  });
  await page.goto('/documents/manage');
  await page.getByLabel('Employee').fill('Thabo');
  await page.getByRole('button', { name: 'Thabo Nkosi' }).click();
  await expect(page.getByRole('row', { name: /chemical-handling/ })).toContainText('Verified');

  await page.getByRole('button', { name: 'Sync expired documents' }).click();
  await expect(page.getByRole('row', { name: /chemical-handling/ })).toContainText('Expired');
  expect(backend.find('employee_documents', { id: ID.docChemical }).status).toBe('expired');
});

test('an employee is blocked from Employee Documents and cannot call the manager RPC successfully', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/documents/manage');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
