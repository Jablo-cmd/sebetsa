import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID } from './utils/sebetsaFixtures';

/** Regions, clients, sites and the contracts list: the organisation structure every other module hangs off. */

test.describe('regions', () => {
  test('lists regions with their codes and status, and links to the detail page', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/regions');
    await expect(page.getByRole('heading', { name: 'Regions' })).toBeVisible();
    await expect(page.getByRole('row', { name: /Gauteng GP active/i })).toBeVisible();
    await expect(page.getByRole('row', { name: /Western Cape WC active/i })).toBeVisible();
    await page.getByRole('link', { name: 'Gauteng' }).click();
    await expect(page.getByRole('heading', { name: 'Gauteng' })).toBeVisible();
    await expect(page.getByRole('link', { name: /Harbour Point – Tower A/ })).toBeVisible();
    await expectNoSeriousViolations(page);
  });

  test('a manager adds, edits and archives a region; validation blocks an empty name', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/regions');
    await page.getByRole('button', { name: 'Add region' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Name is required')).toBeVisible();
    expect(backend.table('regions')).toHaveLength(2);

    await dialog.getByLabel('Name').fill('KwaZulu-Natal');
    await dialog.getByLabel('Code').fill('KZN');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('row', { name: /KwaZulu-Natal KZN active/i })).toBeVisible();
    expect(backend.find('regions', { name: 'KwaZulu-Natal' })).toMatchObject({ code: 'KZN', tenant_id: ID.org });

    await page.getByRole('row', { name: /KwaZulu-Natal/ }).getByRole('button', { name: 'Edit' }).click();
    await page.getByRole('dialog').getByLabel('Code').fill('KN');
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('row', { name: /KwaZulu-Natal KN/i })).toBeVisible();

    await page.getByRole('row', { name: /KwaZulu-Natal/ }).getByRole('button', { name: 'Archive' }).click();
    await expect(page.getByRole('row', { name: /KwaZulu-Natal/ }).getByRole('cell', { name: 'inactive' })).toBeVisible();
    await page.getByRole('row', { name: /KwaZulu-Natal/ }).getByRole('button', { name: 'Restore' }).click();
    await expect(page.getByRole('row', { name: /KwaZulu-Natal/ }).getByRole('cell', { name: 'active', exact: true })).toBeVisible();
    expect(backend.find('regions', { name: 'KwaZulu-Natal' }).status).toBe('active');
  });

  test('a duplicate region name is refused with a clear message', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/regions');
    await page.getByRole('button', { name: 'Add region' }).click();
    await page.getByRole('dialog').getByLabel('Name').fill('Gauteng');
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog').getByRole('alert')).toContainText('already exists');
    expect(backend.table('regions')).toHaveLength(2);
  });

  test('read-only roles see regions without management actions', async ({ page, app }) => {
    await app.open('regional_manager');
    await page.goto('/regions');
    await expect(page.getByRole('row', { name: /Gauteng/ })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add region' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Edit' })).toHaveCount(0);
  });

  test('another tenant\'s region is "not found"', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/regions/00000000-0000-4000-8000-00ee00000002');
    await expect(page.getByText('Region not found')).toBeVisible();
  });
});

test.describe('clients', () => {
  test('lists clients, filters by search, region and status, and never shows another tenant\'s clients', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/clients');
    await expect(page.getByRole('row', { name: /Harbour Point Offices/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Northgate Mall/ })).toBeVisible();
    await expect(page.getByText('Rival Client Ltd')).toHaveCount(0);

    await page.getByLabel('Search clients').fill('retail');
    await expect(page.getByRole('row', { name: /Northgate Mall/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Harbour Point/ })).toHaveCount(0);

    await page.getByLabel('Search clients').fill('');
    await page.getByLabel('Filter by region').selectOption(ID.regionWesternCape);
    await expect(page.getByText('No clients match your filters.')).toBeVisible();
    await page.getByLabel('Filter by region').selectOption('');
    await page.getByLabel('Filter by status').selectOption('onboarding');
    await expect(page.getByText('No clients match your filters.')).toBeVisible();
  });

  test('a manager adds a client with validation, then it appears in the list', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/clients');
    await page.getByRole('button', { name: 'Add client' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Name is required')).toBeVisible();

    await dialog.getByLabel('Client name').fill('Bayside Hospital');
    await dialog.getByLabel('Contact email').fill('not-an-email');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Enter a valid email address')).toBeVisible();

    await dialog.getByLabel('Contact email').fill('facilities@bayside.example');
    await dialog.getByLabel('Region').selectOption(ID.regionWesternCape);
    await dialog.getByLabel('Industry').fill('Healthcare');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('row', { name: /Bayside Hospital Western Cape Healthcare active/i })).toBeVisible();
    expect(backend.find('clients', { name: 'Bayside Hospital' })).toMatchObject({ tenant_id: ID.org, region_id: ID.regionWesternCape, primary_contact_email: 'facilities@bayside.example' });
  });

  test('client detail shows contacts, sites and contracts; a manager can add a named contact', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto(`/clients/${ID.clientHarbour}`);
    await expect(page.getByRole('heading', { name: 'Harbour Point Offices' })).toBeVisible();
    await expect(page.getByText('Chris Client').first()).toBeVisible();
    await expect(page.getByRole('link', { name: /Harbour Point – Tower A/ })).toBeVisible();
    await expect(page.getByRole('link', { name: /HP-2026-001/ })).toBeVisible();

    const add = page.getByRole('button', { name: 'Add contact' });
    await expect(add).toBeDisabled();
    await page.getByLabel('Name', { exact: true }).fill('Dana Ops');
    await page.getByLabel('Role').fill('Operations Lead');
    await add.click();
    await expect(page.getByText('Dana Ops')).toBeVisible();
    expect(backend.find('client_contacts', { name: 'Dana Ops' })).toMatchObject({ client_id: ID.clientHarbour, role_title: 'Operations Lead', tenant_id: ID.org });
    await expectNoSeriousViolations(page);
  });

  test('a manager edits and archives a client from its detail page', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto(`/clients/${ID.clientNorthgate}`);
    await page.getByRole('button', { name: 'Edit details' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByLabel('Client name')).toHaveValue('Northgate Mall');
    await dialog.getByLabel('Industry').fill('Retail property');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByText('Retail property')).toBeVisible();
    expect(backend.find('clients', { id: ID.clientNorthgate }).industry).toBe('Retail property');

    await page.getByLabel('Client status').selectOption('inactive');
    await expect(page.getByLabel('Client status')).toHaveValue('inactive');
    expect(backend.find('clients', { id: ID.clientNorthgate }).status).toBe('inactive');
    await page.getByLabel('Client status').selectOption('active');
    await expect(page.getByLabel('Client status')).toHaveValue('active');
    expect(backend.find('clients', { id: ID.clientNorthgate }).status).toBe('active');
  });

  test('a failed archive is reported and the status is unchanged', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto(`/clients/${ID.clientNorthgate}`);
    backend.fault('clients', { method: 'PATCH', times: 1 });
    await page.getByLabel('Client status').selectOption('inactive');
    await expect(page.getByText('Failed to update the client.')).toBeVisible();
    await expect(page.getByLabel('Client status')).toHaveValue('active');
    expect(backend.find('clients', { id: ID.clientNorthgate }).status).toBe('active');
  });

  test('roles that cannot manage org structure get read-only client pages', async ({ page, app }) => {
    await app.open('site_manager');
    await page.goto('/clients');
    await expect(page.getByRole('button', { name: 'Add client' })).toHaveCount(0);
    await page.goto(`/clients/${ID.clientHarbour}`);
    await expect(page.getByRole('heading', { name: 'Harbour Point Offices' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Edit details' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Add contact' })).toHaveCount(0);
  });

  test('a client in another tenant is "not found"', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto(`/clients/${ID.rivalClient}`);
    await expect(page.getByText('Client not found')).toBeVisible();
  });
});

test.describe('sites', () => {
  test('lists sites with client and region, and filters them', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/sites');
    await expect(page.getByRole('row', { name: /Harbour Point – Tower A.*Harbour Point Offices.*Gauteng/ })).toBeVisible();
    await expect(page.getByText('Rival Site')).toHaveCount(0);

    await page.getByLabel('Filter by client').selectOption(ID.clientNorthgate);
    await expect(page.getByRole('row', { name: /Main Atrium/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Tower A/ })).toHaveCount(0);
    await page.getByLabel('Search sites').fill('food');
    await expect(page.getByRole('row', { name: /Food Court/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Main Atrium/ })).toHaveCount(0);
  });

  test('a manager adds a site for a client', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/sites');
    await page.getByRole('button', { name: 'Add site' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Name is required')).toBeVisible();
    await expect(dialog.getByText('Client is required')).toBeVisible();

    await dialog.getByLabel('Site name').fill('Northgate – Car Park');
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientNorthgate);
    await dialog.getByLabel('Address').fill('2 Northgate Drive');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('row', { name: /Northgate – Car Park/ })).toBeVisible();
    expect(backend.find('sites', { name: 'Northgate – Car Park' })).toMatchObject({ client_id: ID.clientNorthgate, tenant_id: ID.org, status: 'onboarding' });
  });

  test('a newly created site starts in onboarding and a manager can activate it', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/sites');
    await page.getByRole('button', { name: 'Add site' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Site name').fill('Northgate – Loading Bay');
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientNorthgate);
    await dialog.getByRole('button', { name: 'Save' }).click();
    await page.getByRole('link', { name: 'Northgate – Loading Bay' }).click();
    await expect(page.getByLabel('Site status')).toHaveValue('onboarding');
    await page.getByLabel('Site status').selectOption('active');
    await expect(page.getByLabel('Site status')).toHaveValue('active');
    expect(backend.find('sites', { name: 'Northgate – Loading Bay' }).status).toBe('active');
  });

  test('a site cannot be created before a client exists', async ({ page, app }) => {
    await app.open('operations_manager', { customize: (t) => (t.clients = t.clients.filter((c) => c.tenant_id !== ID.org)) });
    await page.goto('/sites');
    await expect(page.getByText('Add a client before creating sites — every site belongs to one.')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add site' })).toBeDisabled();
  });

  test('site detail shows client, region, contracts and the current workforce; a manager edits and archives it', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto(`/sites/${ID.siteTowerA}`);
    await expect(page.getByRole('heading', { name: 'Harbour Point – Tower A' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Harbour Point Offices' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Gauteng' })).toBeVisible();
    await expect(page.getByRole('link', { name: /HP-2026-001/ })).toBeVisible();
    await expect(page.getByText('Thabo Nkosi')).toBeVisible();

    await page.getByRole('button', { name: 'Edit details' }).click();
    await page.getByRole('dialog').getByLabel('Address').fill('12 Harbour Street, Sandton');
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText('12 Harbour Street, Sandton')).toBeVisible();
    expect(backend.find('sites', { id: ID.siteTowerA }).address).toBe('12 Harbour Street, Sandton');

    await page.getByLabel('Site status').selectOption('offboarded');
    await expect(page.getByLabel('Site status')).toHaveValue('offboarded');
    expect(backend.find('sites', { id: ID.siteTowerA }).status).toBe('offboarded');
    await expectNoSeriousViolations(page);
  });

  test('a failure while resolving workforce names is shown', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    backend.fault('employees', { method: 'GET' });
    await page.goto(`/sites/${ID.siteTowerA}`);
    await expect(page.getByText('Failed to load the workforce names.')).toBeVisible();
  });

  test('a site in another tenant is "not found"', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto(`/sites/${ID.rivalSite}`);
    await expect(page.getByText('Site not found')).toBeVisible();
  });
});

test.describe('contracts list', () => {
  test('lists contracts with their client and dates and filters them', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/contracts');
    await expect(page.getByRole('row', { name: /HP-2026-001.*Harbour Point Offices.*2026-01-01.*2026-12-31.*active/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /NG-2026-002/ })).toBeVisible();

    await page.getByLabel('Search contracts').fill('NG-');
    await expect(page.getByRole('row', { name: /HP-2026-001/ })).toHaveCount(0);
    await page.getByLabel('Search contracts').fill('');
    await page.getByLabel('Filter by client').selectOption(ID.clientHarbour);
    await expect(page.getByRole('row', { name: /NG-2026-002/ })).toHaveCount(0);
    await page.getByLabel('Filter by client').selectOption('');
    await page.getByLabel('Filter by status').selectOption('terminated');
    await expect(page.getByText('No contracts match your filters.')).toBeVisible();
  });

  test('a manager creates a contract covering chosen sites of its client', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/contracts');
    await page.getByRole('button', { name: 'Add contract' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Client is required')).toBeVisible();
    await expect(dialog.getByText('Contract number is required')).toBeVisible();
    await expect(dialog.getByText('Start date is required')).toBeVisible();

    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientNorthgate);
    await dialog.getByLabel('Contract number').fill('NG-2027-001');
    await dialog.getByLabel('Start date').fill('2027-01-01');
    await dialog.getByRole('checkbox', { name: /Main Atrium/ }).check();
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('row', { name: /NG-2027-001/ })).toBeVisible();
    const created = backend.find('contracts', { contract_number: 'NG-2027-001' });
    expect(created).toMatchObject({ client_id: ID.clientNorthgate, tenant_id: ID.org, start_date: '2027-01-01' });
    expect(backend.table('contract_sites').filter((l) => l.contract_id === created.id).map((l) => l.site_id)).toEqual([ID.siteAtrium]);
  });

  test('only the chosen client\'s sites are offered, and switching client clears the selection', async ({ page, app }) => {
    await app.open('operations_manager');
    await page.goto('/contracts');
    await page.getByRole('button', { name: 'Add contract' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText('Select a client to choose which sites this contract covers.')).toBeVisible();
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientNorthgate);
    await expect(dialog.getByRole('checkbox', { name: /Main Atrium/ })).toBeVisible();
    await expect(dialog.getByRole('checkbox', { name: /Tower A/ })).toHaveCount(0);
    await dialog.getByRole('checkbox', { name: /Main Atrium/ }).check();
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientHarbour);
    await expect(dialog.getByRole('checkbox', { name: /Tower A/ })).not.toBeChecked();
  });

  test('a duplicate contract number is refused', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/contracts');
    await page.getByRole('button', { name: 'Add contract' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientHarbour);
    await dialog.getByLabel('Contract number').fill('HP-2026-001');
    await dialog.getByLabel('Start date').fill('2027-01-01');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByRole('alert')).toContainText('already exists');
    expect(backend.table('contracts').filter((c) => c.tenant_id === ID.org)).toHaveLength(2);
  });

  test('when the sites cannot be linked the contract is kept and the user is told what to do', async ({ page, app }) => {
    const backend = await app.open('operations_manager', {
      rpc: { set_contract_sites: (_a, ctx) => ctx.fail('boom', 'XX000', 500) },
    });
    await page.goto('/contracts');
    await page.getByRole('button', { name: 'Add contract' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Client', { exact: false }).first().selectOption(ID.clientNorthgate);
    await dialog.getByLabel('Contract number').fill('NG-2027-002');
    await dialog.getByLabel('Start date').fill('2027-02-01');
    await dialog.getByRole('checkbox', { name: /Food Court/ }).check();
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByRole('alert')).toContainText('NG-2027-002 was created, but its sites could not be linked');
    expect(backend.find('contracts', { contract_number: 'NG-2027-002' })).toBeTruthy();
  });

  test('read-only roles cannot add contracts', async ({ page, app }) => {
    await app.open('site_manager');
    await page.goto('/contracts');
    await expect(page.getByRole('row', { name: /HP-2026-001/ })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add contract' })).toHaveCount(0);
  });
});
