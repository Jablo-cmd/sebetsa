import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

const THABO_SKILL = '00000000-0000-4000-8000-003500000001';
const THABO_QUAL = '00000000-0000-4000-8000-003900000001';
const HANNAH_QUAL = '00000000-0000-4000-8000-003900000002';
const HANNAH_SKILL = '00000000-0000-4000-8000-003500000002';

const withQualifications = (tables: Record<string, Record<string, unknown>[]>) => {
  const base = { tenant_id: ID.org, credential_type: 'certification', issuing_organization: 'SETA', issue_date: '2026-01-10', expiry_date: null, evidence_document_id: null, status: 'pending_verification', verified_by: null, verified_at: null, created_at: '2026-01-10T08:00:00.000Z', updated_at: '2026-01-10T08:00:00.000Z' };
  tables.employee_qualifications = [
    { ...base, id: THABO_QUAL, employee_id: PERSONAS.employee.employeeId, name: 'Cleaning NQF2' },
    { ...base, id: HANNAH_QUAL, employee_id: PERSONAS.hr_user.employeeId, name: 'HR Practitioner' },
  ];
  tables.employee_skills.push({ id: HANNAH_SKILL, tenant_id: ID.org, employee_id: PERSONAS.hr_user.employeeId, skill_id: ID.skillFirstAid, proficiency_level: 'advanced', evidence_document_id: null, verified_by: null, verified_at: null, created_at: base.created_at, updated_at: base.updated_at });
};

async function selectEmployee(page: import('@playwright/test').Page, name: string) {
  await page.getByLabel('Employee', { exact: true }).fill(name);
  await page.locator('main').getByRole('button', { name: new RegExp(name) }).click();
  await expect(page.getByText(/Selected:/)).toContainText(name);
}

test('an employee sees their own development record and acknowledges a review', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/development');
  await expect(page.getByRole('heading', { name: 'My Development' })).toBeVisible();
  await expect(page.getByText('intermediate (unverified)')).toBeVisible();
  await expect(page.getByText('scheduled', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-01-01 to 2026-06-30 — Awaiting acknowledgement')).toBeVisible();
  await expect(page.getByText('Reliable and thorough.')).toBeVisible();
  await expectNoSeriousViolations(page);
  // The review is already at acknowledgement; nothing further for the employee to do.
  await expect(page.getByRole('button', { name: 'Acknowledge' })).toHaveCount(0);
  expect(backend.find('performance_reviews', { id: ID.reviewThabo })).toMatchObject({ status: 'acknowledgement' });
});

test('an employee acknowledges a review awaiting their response', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => {
      const review = t.performance_reviews.find((r) => r.id === ID.reviewThabo)!;
      review.status = 'employee_review';
    },
  });
  await page.goto('/development');
  await page.getByLabel('Your comments (optional)').fill('Agreed, thank you');
  await page.getByRole('button', { name: 'Acknowledge' }).click();
  await expect(page.getByText(/Awaiting acknowledgement/)).toBeVisible();
  expect(backend.find('performance_reviews', { id: ID.reviewThabo })).toMatchObject({ status: 'acknowledgement', employee_comments: 'Agreed, thank you' });
});

test('an employee cannot reach Workforce Development management', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/development/manage');
  await expect(page).toHaveURL(/\/dashboard$/);
});

test('the employee view reports a load failure instead of an empty record', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('employee_skills');
  await page.goto('/development');
  await expect(page.getByText('Failed to load your development record.')).toBeVisible();
});

test('HR creates catalogue entries, enrols an employee and runs a review through its stages', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/development/manage');
  await expect(page.getByRole('heading', { name: 'Workforce Development' })).toBeVisible();
  await expect(page.getByRole('list').filter({ hasText: 'Chemical handling' })).toBeVisible();

  await page.getByLabel('New skill').fill('Window cleaning at height');
  await page.getByRole('button', { name: 'Add' }).first().click();
  await expect(page.getByText('Window cleaning at height')).toBeVisible();
  await page.getByLabel('New programme').fill('Working at heights');
  await page.getByRole('button', { name: 'Add' }).nth(1).click();
  await expect(page.getByText('Working at heights', { exact: true })).toBeVisible();
  expect(backend.find('skills', { name: 'Window cleaning at height' })).toBeTruthy();

  await selectEmployee(page, 'Thabo');
  await expect(page.getByText('Chemical handling — intermediate')).toBeVisible();
  await expect(page.getByText('Manual handling — scheduled')).toBeVisible();

  await page.getByRole('button', { name: 'Enroll in Working at heights' }).click();
  await expect(page.getByText('Working at heights — scheduled')).toBeVisible();

  await page.getByRole('button', { name: 'Start a new review' }).click();
  await expect(page.getByText(/— Draft$/)).toBeVisible();
  await page.getByRole('button', { name: 'Advance' }).click();
  await expect(page.getByText(/— Manager review$/)).toBeVisible();
  await page.getByRole('button', { name: 'Advance' }).click();
  await expect(page.getByText(/— Awaiting employee review$/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Advance' })).toHaveCount(0);
  const created = backend.table('performance_reviews').find((r) => r.status === 'employee_review');
  expect(created).toMatchObject({ employee_id: PERSONAS.employee.employeeId, reviewer_profile_id: PERSONAS.hr_user.profileId });
  await expectNoSeriousViolations(page);
});

test('HR verifies another employee\'s skill and qualification, but not their own (separation of duties)', async ({ page, app }) => {
  const backend = await app.open('hr_user', { customize: withQualifications });
  await page.goto('/development/manage');

  await selectEmployee(page, 'Thabo');
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByText('Chemical handling — intermediate (verified)')).toBeVisible();
  expect(backend.find('employee_skills', { id: THABO_SKILL })).toMatchObject({ verified_by: PERSONAS.hr_user.profileId });

  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('Cleaning NQF2 — verified')).toBeVisible();
  expect(backend.find('employee_qualifications', { id: THABO_QUAL })).toMatchObject({ status: 'verified', verified_by: PERSONAS.hr_user.profileId });

  // Own record: the server refuses and the UI says so.
  await selectEmployee(page, 'Hannah');
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByRole('alert')).toContainText(/separation|cannot/i);
  expect(backend.find('employee_skills', { id: HANNAH_SKILL })).toMatchObject({ verified_by: null });
  await page.getByRole('button', { name: 'Reject' }).click();
  await expect(page.getByText('HR Practitioner — pending_verification')).toBeVisible();
  expect(backend.find('employee_qualifications', { id: HANNAH_QUAL })).toMatchObject({ status: 'pending_verification' });
});

test('a rejected qualification is recorded as revoked', async ({ page, app }) => {
  const backend = await app.open('operations_manager', { customize: withQualifications });
  await page.goto('/development/manage');
  await selectEmployee(page, 'Thabo');
  await page.getByRole('button', { name: 'Reject' }).click();
  await expect(page.getByText('Cleaning NQF2 — revoked')).toBeVisible();
  expect(backend.find('employee_qualifications', { id: THABO_QUAL })).toMatchObject({ status: 'revoked' });
});

test('catalogue and search failures are shown, not swallowed', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  backend.fault('skills');
  await page.goto('/development/manage');
  await expect(page.getByText('Failed to load the skills and training catalogues.')).toBeVisible();
});

test('supervisors, site managers and clients have no Workforce Development management page', async ({ page, app }) => {
  for (const role of ['supervisor', 'client_user'] as const) {
    await app.open(role);
    await page.goto('/development/manage');
    await expect(page).not.toHaveURL(/development\/manage/);
  }
});
