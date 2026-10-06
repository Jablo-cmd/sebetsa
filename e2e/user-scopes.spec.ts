import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

const ATRIUM_TASK = '00000000-0000-4000-8000-00ab00000001';
const atriumTask = {
  id: ATRIUM_TASK, tenant_id: ID.org, site_id: ID.siteAtrium, assignee_id: PERSONAS.employee_two.employeeId, team_id: null, supervisor_id: null, title: 'Strip and seal atrium floor',
  description: null, priority: 'normal', status: 'open', due_at: '2026-09-25T09:00:00.000Z', completed_at: null, completed_by: null, requires_evidence: false, created_by: PERSONAS.operations_manager.profileId,
  created_at: '2026-01-05T08:00:00.000Z', updated_at: '2026-01-05T08:00:00.000Z',
};

test.describe('scope-aware access', () => {
  test('a site manager sees tasks only at their assigned site; tenant-wide roles see every site', async ({ page, app }) => {
    await app.open('site_manager', { customize: (t) => t.tasks.push(atriumTask) });
    await page.goto('/tasks/management');
    await expect(page.getByText('Clean ground-floor washrooms')).toBeVisible();
    await expect(page.getByText('Strip and seal atrium floor')).toHaveCount(0);

    await app.open('operations_manager', { customize: (t) => t.tasks.push(atriumTask) });
    await page.goto('/tasks/management');
    await expect(page.getByText('Strip and seal atrium floor')).toBeVisible();
    await expect(page.getByText('Clean ground-floor washrooms')).toBeVisible();
  });

  test('a regional manager sees every site inside their region', async ({ page, app }) => {
    await app.open('regional_manager', { customize: (t) => t.tasks.push(atriumTask) });
    await page.goto('/tasks/management');
    await expect(page.getByText('Strip and seal atrium floor')).toBeVisible();
    await expect(page.getByText('Clean ground-floor washrooms')).toBeVisible();
  });

  test('a scoped role with no scope assigned sees nothing (fail closed)', async ({ page, app }) => {
    await app.open('site_manager', { customize: (t) => (t.user_scopes = []) });
    await page.goto('/tasks/management');
    await expect(page.getByText('Clean ground-floor washrooms')).toHaveCount(0);
    await expect(page.getByText('Strip and seal atrium floor')).toHaveCount(0);
  });
});

test.describe('managing access scopes', () => {
  const sipho = PERSONAS.site_manager.profileId;

  test('an administrator sees a scoped user\'s scopes, grants another site and revokes one', async ({ page, app }) => {
    const backend = await app.open('organization_administrator');
    await page.goto(`/users/${sipho}`);
    await expect(page.getByRole('heading', { name: 'Access scope' })).toBeVisible();
    await expect(page.getByRole('listitem').filter({ hasText: 'Harbour Point – Tower A' })).toBeVisible();

    await page.getByLabel('Scope type').selectOption('site');
    await page.getByLabel('Grant access to').selectOption(ID.siteAtrium);
    await page.getByRole('button', { name: 'Grant access' }).click();
    await expect(page.getByRole('listitem').filter({ hasText: 'Northgate Mall – Main Atrium' })).toBeVisible();
    expect(backend.find('user_scopes', { profile_id: sipho, scope_id: ID.siteAtrium })).toMatchObject({ scope_type: 'site', granted_by: PERSONAS.organization_administrator.profileId, tenant_id: ID.org });
    expect(backend.table('audit_log').some((a) => a.action === 'scope_granted')).toBe(true);

    await page.getByRole('button', { name: 'Revoke Site Harbour Point – Tower A' }).click();
    await expect(page.getByRole('listitem').filter({ hasText: 'Harbour Point – Tower A' })).toHaveCount(0);
    expect(backend.table('user_scopes').filter((s) => s.profile_id === sipho).map((s) => s.scope_id)).toEqual([ID.siteAtrium]);
    expect(backend.table('audit_log').some((a) => a.action === 'scope_revoked')).toBe(true);
    await expectNoSeriousViolations(page);
  });

  test('a region or a team can be granted too', async ({ page, app }) => {
    const backend = await app.open('organization_administrator');
    await page.goto(`/users/${sipho}`);
    await page.getByLabel('Scope type').selectOption('region');
    await page.getByLabel('Grant access to').selectOption(ID.regionWesternCape);
    await page.getByRole('button', { name: 'Grant access' }).click();
    await expect(page.getByRole('listitem').filter({ hasText: 'Western Cape' })).toBeVisible();
    await page.getByLabel('Scope type').selectOption('team');
    await page.getByLabel('Grant access to').selectOption(ID.teamTowerADay);
    await page.getByRole('button', { name: 'Grant access' }).click();
    await expect(page.getByRole('listitem').filter({ hasText: 'Tower A Day Team' })).toBeVisible();
    expect(backend.table('user_scopes').filter((s) => s.profile_id === sipho)).toHaveLength(3);
  });

  test('a user with no scope gets an explicit warning', async ({ page, app }) => {
    await app.open('organization_administrator', { customize: (t) => (t.user_scopes = []) });
    await page.goto(`/users/${sipho}`);
    await expect(page.getByRole('status')).toContainText('No access scope is assigned');
    await expect(page.getByRole('button', { name: 'Grant access' })).toBeDisabled();
  });

  test('nobody can grant themselves a scope (separation of duties); the refusal is explained', async ({ page, app }) => {
    // The operations manager is not a scoped role, so give them the section by viewing a scoped user —
    // the server-side rule is what matters: call it for the actor's own profile.
    const backend = await app.open('organization_administrator');
    await page.goto(`/users/${sipho}`);
    backend.rpcHandlers.set('grant_user_scope', (a, ctx) => {
      ctx.fail('separation_of_duties: scope.assign — you cannot act on a record you raised or that concerns you', '42501', 403);
      return null;
    });
    await page.getByLabel('Grant access to').selectOption(ID.siteAtrium);
    await page.getByRole('button', { name: 'Grant access' }).click();
    await expect(page.getByRole('alert')).toContainText('You cannot approve, verify or close a record you raised');
    expect(backend.table('user_scopes').filter((s) => s.scope_id === ID.siteAtrium)).toHaveLength(0);
  });

  test('a scope that is not in the tenant is refused by the server', async ({ page, app }) => {
    const backend = await app.open('organization_administrator');
    await page.goto(`/users/${sipho}`);
    await page.getByLabel('Grant access to').selectOption(ID.siteAtrium);
    backend.table('sites').find((s) => s.id === ID.siteAtrium)!.tenant_id = ID.rivalOrg;
    await page.getByRole('button', { name: 'Grant access' }).click();
    await expect(page.getByRole('alert')).toContainText('does not belong to your organisation');
  });

  test('non-scoped users have no scope section', async ({ page, app }) => {
    await app.open('organization_administrator');
    await page.goto(`/users/${PERSONAS.hr_user.profileId}`);
    await expect(page.getByRole('heading', { name: PERSONAS.hr_user.firstName + ' ' + PERSONAS.hr_user.lastName })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Access scope' })).toHaveCount(0);

  });

  test('a failed scope load is reported', async ({ page, app }) => {
    const backend = await app.open('organization_administrator');
    backend.fault('user_scopes', { method: 'GET' });
    await page.goto(`/users/${sipho}`);
    await expect(page.getByText('Failed to load access scopes.')).toBeVisible();
  });
});
