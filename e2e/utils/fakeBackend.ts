import type { Page, Request, Route } from '@playwright/test';
import { COLUMN_DEFAULTS, CURRENT_DATE_DEFAULTS, ON_DELETE, TABLE_COLUMNS, UNIQUE_KEYS } from './schemaDefaults';

/**
 * Sebetsa's single, authoritative E2E backend.
 *
 * A stateful, in-memory stand-in for the parts of Supabase the app talks to
 * (PostgREST tables, RPCs, Storage, GoTrue). It deliberately behaves like the
 * real thing where the UI depends on it:
 *
 *   - PostgREST filters (eq/neq/gt/gte/lt/lte/in/is/ilike/like/or/not), order,
 *     limit/offset, exact counts, single-object responses (406 PGRST116),
 *     insert/upsert/patch/delete with `return=representation`.
 *   - Tenant isolation like RLS: rows whose tenant_id is not the session's
 *     tenant are invisible and cannot be written (42501), unless the session
 *     is a platform administrator.
 *   - Unique constraints (23505) where the schema has them.
 *   - Unknown tables, RPCs and endpoints FAIL THE TEST: they are recorded in
 *     `unmocked` and answered 501, and the strict-network fixture
 *     (e2e/utils/test.ts) asserts the list is empty after every test.
 *
 * Nothing here ever reaches a real Supabase project: every request to the
 * configured Supabase origin must be handled in-process.
 */

export type Row = Record<string, unknown>;

export interface RecordedRequest {
  method: string;
  path: string;
  query: Record<string, string>;
  body: unknown;
  table?: string;
  rpc?: string;
}

export interface Session {
  userId: string;
  tenantId: string | null;
  role: string;
  email: string;
  /** MFA factors on the auth user (what mfaService reads from the session). */
  factors?: { id: string; factor_type: 'totp' | 'phone'; status: 'verified' | 'unverified' }[];
  /** Authenticator assurance level of the session's token (aal2 = MFA step-up completed). */
  aal?: 'aal1' | 'aal2';
}

export interface RpcContext {
  backend: FakeBackend;
  session: Session;
  now: string;
  /** Throws a PostgREST-style error the app maps through getDbErrorMessage(). */
  fail(message: string, code?: string, status?: number): never;
}

export type RpcHandler = (args: Row, ctx: RpcContext) => unknown | Promise<unknown>;

/** Every table the app queries. Must exist in supabase/migrations (see fakeBackend.unit.ts). */
export const KNOWN_TABLES = [
  'asset_assignments',
  'asset_maintenance_records',
  'assets',
  'attendance_breaks',
  'attendance_corrections',
  'attendance_policies',
  'attendance_records',
  'audit_log',
  'client_contacts',
  'clients',
  'compliance_records',
  'compliance_requirements',
  'contract_documents',
  'contract_sites',
  'contracts',
  'departments',
  'development_actions',
  'employee_availability',
  'employee_availability_exceptions',
  'employee_documents',
  'employee_qualifications',
  'employee_skills',
  'employees',
  'incident_actions',
  'incident_affected_employees',
  'incidents',
  'inventory_items',
  'inventory_movements',
  'leave_balance_transactions',
  'leave_balances',
  'leave_policies',
  'leave_requests',
  'leave_types',
  'notification_preferences',
  'notifications',
  'organizations',
  'performance_reviews',
  'positions',
  'procurement_requests',
  'profiles',
  'regions',
  'shift_definitions',
  'shift_substitutions',
  'shifts',
  'site_assignments',
  'site_staffing_requirements',
  'sites',
  'skills',
  'sla_definitions',
  'sla_measurements',
  'task_checklist_items',
  'task_comments',
  'task_evidence',
  'task_templates',
  'tasks',
  'team_members',
  'teams',
  'training_enrollments',
  'training_programs',
  'training_requirements',
  'user_scopes',
] as const;

/** Tables with a RESTRICTIVE scope policy (see the 20261007090000 migration). */
const SCOPED_TABLES = ['shifts', 'attendance_records', 'tasks', 'incidents', 'compliance_records', 'assets', 'inventory_movements', 'procurement_requests'];
const SCOPED_ROLES = ['regional_manager', 'site_manager', 'supervisor'];

/** Server-derived authorship columns (set_actor_column triggers): the caller, never what the client sent. */
const ACTOR_COLUMNS: Record<string, string> = {
  task_evidence: 'submitted_by',
  task_comments: 'author_id',
  tasks: 'created_by',
  compliance_requirements: 'created_by',
  inventory_movements: 'performed_by',
  attendance_records: 'recorded_by',
};

export class RpcFailure extends Error {
  constructor(
    message: string,
    public code = 'P0001',
    public status = 400,
  ) {
    super(message);
  }
}

const ISO = /^\d{4}-\d{2}-\d{2}/;

function compare(a: unknown, b: string): number {
  if (typeof a === 'number' || (typeof a === 'string' && a !== '' && !ISO.test(a) && !Number.isNaN(Number(a)) && !Number.isNaN(Number(b)))) {
    return Number(a) - Number(b);
  }
  const s = a === null || a === undefined ? '' : String(a);
  return s < b ? -1 : s > b ? 1 : 0;
}

function likeToRegex(pattern: string, caseInsensitive: boolean): RegExp {
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*').replace(/_/g, '.');
  return new RegExp(`^${escaped}$`, caseInsensitive ? 'i' : '');
}

function matchCondition(row: Row, column: string, operatorAndValue: string): boolean {
  let negate = false;
  let rest = operatorAndValue;
  if (rest.startsWith('not.')) {
    negate = true;
    rest = rest.slice(4);
  }
  const dot = rest.indexOf('.');
  const op = rest.slice(0, dot);
  const value = rest.slice(dot + 1);
  const cell = row[column];
  let result: boolean;
  switch (op) {
    case 'eq':
      result = cell !== null && cell !== undefined && String(cell) === value;
      break;
    case 'neq':
      result = cell === null || cell === undefined || String(cell) !== value;
      break;
    case 'gt':
      result = cell !== null && cell !== undefined && compare(cell, value) > 0;
      break;
    case 'gte':
      result = cell !== null && cell !== undefined && compare(cell, value) >= 0;
      break;
    case 'lt':
      result = cell !== null && cell !== undefined && compare(cell, value) < 0;
      break;
    case 'lte':
      result = cell !== null && cell !== undefined && compare(cell, value) <= 0;
      break;
    case 'is':
      result =
        value === 'null'
          ? cell === null || cell === undefined
          : value === 'true'
            ? cell === true
            : value === 'false'
              ? cell === false
              : false;
      break;
    case 'in': {
      const items = value
        .replace(/^\(/, '')
        .replace(/\)$/, '')
        .split(',')
        .map((v) => v.replace(/^"|"$/g, ''));
      result = cell !== null && cell !== undefined && items.includes(String(cell));
      break;
    }
    case 'like':
    case 'ilike':
      result = cell !== null && cell !== undefined && likeToRegex(value, op === 'ilike').test(String(cell));
      break;
    default:
      throw new RpcFailure(`fake backend: unsupported filter operator "${op}"`, 'PGRST100', 400);
  }
  return negate ? !result : result;
}

function splitTopLevel(input: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let current = '';
  for (const ch of input) {
    if (ch === '(') depth += 1;
    if (ch === ')') depth -= 1;
    if (ch === ',' && depth === 0) {
      parts.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  if (current) parts.push(current);
  return parts;
}

const RESERVED_PARAMS = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'columns']);

/** `entries` keeps repeated keys: `created_at=gte.A&created_at=lte.B` is two filters, not one. */
function applyFilters(rows: Row[], entries: [string, string][]): Row[] {
  let result = rows;
  for (const [key, raw] of entries) {
    if (RESERVED_PARAMS.has(key)) continue;
    if (key === 'or') {
      const conditions = splitTopLevel(raw.replace(/^\(/, '').replace(/\)$/, ''));
      result = result.filter((row) =>
        conditions.some((condition) => {
          const firstDot = condition.indexOf('.');
          return matchCondition(row, condition.slice(0, firstDot), condition.slice(firstDot + 1));
        }),
      );
      continue;
    }
    result = result.filter((row) => matchCondition(row, key, raw));
  }
  return result;
}

function applyOrder(rows: Row[], order: string | undefined): Row[] {
  if (!order) return rows;
  const specs = order.split(',').map((spec) => {
    const [column, ...flags] = spec.split('.');
    return { column, desc: flags.includes('desc'), nullsFirst: flags.includes('nullsfirst') };
  });
  return [...rows].sort((a, b) => {
    for (const { column, desc, nullsFirst } of specs) {
      const av = a[column];
      const bv = b[column];
      const aNull = av === null || av === undefined;
      const bNull = bv === null || bv === undefined;
      if (aNull || bNull) {
        if (aNull && bNull) continue;
        // PostgREST default: nulls last for asc, first for desc.
        const nullsAreFirst = nullsFirst || (desc && !flags(order, column).includes('nullslast'));
        return aNull ? (nullsAreFirst ? -1 : 1) : nullsAreFirst ? 1 : -1;
      }
      const cmp = compare(av, String(bv));
      if (cmp !== 0) return desc ? -cmp : cmp;
    }
    return 0;
  });
}

function flags(order: string, column: string): string[] {
  const spec = order.split(',').find((s) => s.split('.')[0] === column) ?? '';
  return spec.split('.').slice(1);
}

/** Resolves `alias:table(cols)` / `table(cols)` embeds by the `<alias>_id` foreign-key convention. */
function embedsOf(select: string): { alias: string; table: string }[] {
  const embeds: { alias: string; table: string }[] = [];
  for (const part of splitTopLevel(select)) {
    const match = /^\s*(?:([a-z_]+):)?([a-z_]+)(?:![a-z_]+)?\(/.exec(part);
    if (match) embeds.push({ alias: match[1] ?? match[2], table: match[2] });
  }
  return embeds;
}

export interface BackendOptions {
  session: Session;
  tables?: Record<string, Row[]>;
  /** ISO timestamp the backend treats as "now" (also pinned in the browser). */
  now: string;
  /** Known auth users for the password grant. Keys are lower-case emails. */
  authUsers?: Record<string, { password: string; session: Session }>;
  rpc?: Record<string, RpcHandler>;
}

export class FakeBackend {
  readonly tables = new Map<string, Row[]>();
  readonly requests: RecordedRequest[] = [];
  readonly unmocked: string[] = [];
  readonly uploads: { bucket: string; path: string; bytes: number; contentType: string | null }[] = [];
  readonly authCalls: { path: string; method: string; body: unknown }[] = [];
  readonly rpcHandlers = new Map<string, RpcHandler>();
  session: Session;
  now: string;
  authUsers: Record<string, { password: string; session: Session }>;
  /** When set, the next N storage uploads fail with a 500. */
  failUploads = 0;
  /** The TOTP code the backend accepts for MFA challenge/verify. */
  mfaCode = '123456';
  /** When set, password recovery requests answer 429. */
  recoverRateLimited = false;
  private counter = 0;
  private readonly faults: { table: string; method?: string; status: number; message: string; code: string; remaining: number }[] = [];

  /**
   * Makes requests to `table` fail (optionally only for one HTTP method),
   * `times` times (default: always). Used to prove error states, retries and
   * that failures are never silently swallowed.
   */
  fault(table: string, options: { method?: string; status?: number; message?: string; code?: string; times?: number } = {}): void {
    this.faults.push({
      table,
      method: options.method,
      status: options.status ?? 500,
      message: options.message ?? 'internal error (injected by the E2E backend)',
      code: options.code ?? 'XX000',
      remaining: options.times ?? Number.POSITIVE_INFINITY,
    });
  }

  private takeFault(table: string, method: string) {
    const fault = this.faults.find((f) => f.table === table && (!f.method || f.method === method) && f.remaining > 0);
    if (fault) fault.remaining -= 1;
    return fault;
  }

  constructor(options: BackendOptions) {
    this.session = options.session;
    this.now = options.now;
    this.authUsers = options.authUsers ?? {};
    for (const table of KNOWN_TABLES) this.tables.set(table, []);
    for (const [table, rows] of Object.entries(options.tables ?? {})) {
      if (!this.tables.has(table)) throw new Error(`fake backend: unknown table "${table}" in fixtures`);
      this.tables.set(table, rows.map((row) => ({ ...row })));
    }
    for (const [name, handler] of Object.entries(options.rpc ?? {})) this.rpcHandlers.set(name, handler);
  }

  table(name: string): Row[] {
    const rows = this.tables.get(name);
    if (!rows) throw new Error(`fake backend: unknown table "${name}"`);
    return rows;
  }

  /** Test helper: the single row matching `where`, or throws. */
  find(name: string, where: Row): Row {
    const found = this.table(name).filter((row) => Object.entries(where).every(([k, v]) => row[k] === v));
    if (found.length !== 1) throw new Error(`fake backend: expected exactly one ${name} row matching ${JSON.stringify(where)}, found ${found.length}`);
    return found[0];
  }

  newId(): string {
    this.counter += 1;
    return `00000000-0000-4000-8000-${String(this.counter).padStart(12, '0')}`;
  }

  /** Rows of `name` visible to the session (tenant isolation like RLS). */
  visible(name: string): Row[] {
    const rows = this.table(name);
    if (this.session.role === 'platform_administrator') return rows;
    if (name === 'organizations') return rows.filter((row) => row.id === this.session.tenantId);
    // profiles_select_own_or_tenant_or_platform_admin: a user always sees their own row.
    if (name === 'profiles') return rows.filter((row) => row.id === this.session.userId || row.tenant_id === this.session.tenantId);
    if (name === 'notifications') return rows.filter((row) => row.recipient_profile_id === this.session.userId);
    // user_scopes_select: your own scopes, or all of the tenant's if you manage org structure.
    if (name === 'user_scopes') {
      const manager = ['organization_administrator', 'operations_manager'].includes(String(this.session.role));
      return rows.filter((row) => row.tenant_id === this.session.tenantId && (manager || row.profile_id === this.session.userId));
    }
    // Restrictive scope policies: regional managers, site managers and supervisors only reach
    // site-bound records inside an assigned region/site/team (fail closed without any scope).
    if (SCOPED_TABLES.includes(name) && SCOPED_ROLES.includes(String(this.session.role))) {
      return rows.filter((row) => row.tenant_id === this.session.tenantId && this.canAccessSite(row.site_id as string | null | undefined));
    }
    return rows.filter((row) => !('tenant_id' in row) || row.tenant_id === this.session.tenantId);
  }

  /** can_access_site(): null-site records are open; otherwise the caller needs a covering scope. */
  canAccessSite(siteId: string | null | undefined): boolean {
    if (!siteId) return true;
    const site = this.table('sites').find((s) => s.id === siteId);
    return this.table('user_scopes').some((scope) => {
      if (scope.profile_id !== this.session.userId) return false;
      if (scope.scope_type === 'site') return scope.scope_id === siteId;
      if (scope.scope_type === 'region') return !!site && site.region_id === scope.scope_id;
      if (scope.scope_type === 'team') return this.table('teams').some((t) => t.id === scope.scope_id && t.site_id === siteId);
      return false;
    });
  }

  private fail(message: string, code = 'P0001', status = 400): never {
    throw new RpcFailure(message, code, status);
  }

  private context(): RpcContext {
    return {
      backend: this,
      session: this.session,
      now: this.now,
      fail: (message, code, status) => this.fail(message, code, status),
    };
  }

  // ---------------------------------------------------------------- install

  async install(page: Page, supabaseOrigin = 'http://localhost:54321'): Promise<void> {
    // Context-level so new tabs/popups (e.g. a signed document URL) are intercepted too.
    await page.context().route(`${supabaseOrigin}/**`, (route) => this.handle(route, supabaseOrigin));
  }

  private async handle(route: Route, origin: string): Promise<void> {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();
    try {
      if (path.startsWith('/rest/v1/rpc/')) return await this.handleRpc(route, request, path.slice('/rest/v1/rpc/'.length));
      if (path.startsWith('/rest/v1/')) return await this.handleTable(route, request, path.slice('/rest/v1/'.length), url);
      if (path.startsWith('/storage/v1/')) return await this.handleStorage(route, request, path, origin);
      if (path.startsWith('/auth/v1/')) return await this.handleAuth(route, request, path);
    } catch (error) {
      if (error instanceof RpcFailure) {
        return json(route, { message: error.message, code: error.code, details: null, hint: null }, error.status);
      }
      throw error;
    }
    return this.reportUnmocked(route, `${method} ${path}`);
  }

  private async reportUnmocked(route: Route, description: string): Promise<void> {
    this.unmocked.push(description);
    await json(route, { message: `unmocked request: ${description}`, code: 'E2E_UNMOCKED' }, 501);
  }

  // ------------------------------------------------------------------- REST

  private async handleTable(route: Route, request: Request, table: string, url: URL): Promise<void> {
    const method = request.method();
    const queryEntries = [...url.searchParams.entries()];
    const query = Object.fromEntries(queryEntries);
    const body = parseBody(request);
    this.requests.push({ method, path: url.pathname, query, body, table });

    if (!this.tables.has(table)) return this.reportUnmocked(route, `${method} /rest/v1/${table} (table not modelled)`);

    const fault = this.takeFault(table, method);
    if (fault) return json(route, { message: fault.message, code: fault.code, details: null, hint: null }, fault.status);

    const prefer = request.headers()['prefer'] ?? '';
    const wantsRepresentation = prefer.includes('return=representation');
    const wantsCount = prefer.includes('count=exact');
    const single = (request.headers()['accept'] ?? '').includes('vnd.pgrst.object');

    if (method === 'GET' || method === 'HEAD') {
      const matched = applyFilters(this.visible(table), queryEntries);
      const total = matched.length;
      let rows = applyOrder(matched, query.order);
      const offset = Number(query.offset ?? 0);
      if (offset) rows = rows.slice(offset);
      if (query.limit !== undefined) rows = rows.slice(0, Number(query.limit));
      const embedded = this.embed(rows, query.select ?? '*');
      const headers: Record<string, string> = {};
      if (wantsCount) {
        headers['content-range'] = `${rows.length ? `${offset}-${offset + rows.length - 1}` : '*'}/${total}`;
        // Cross-origin: the browser only hands the count to supabase-js if the header is exposed.
        headers['access-control-expose-headers'] = 'content-range';
      }
      if (method === 'HEAD') return route.fulfill({ status: 200, headers });
      return respondRows(route, embedded, single, headers);
    }

    if (method === 'POST') {
      const incoming = (Array.isArray(body) ? body : [body]) as Row[];
      const upsert = prefer.includes('resolution=merge-duplicates');
      const created: Row[] = [];
      for (const payload of incoming) {
        const row = this.prepareInsert(table, payload);
        if (upsert) {
          const conflictCols = (query.on_conflict ?? 'id').split(',');
          const existing = this.table(table).find((r) => conflictCols.every((c) => r[c] === row[c]));
          if (existing) {
            Object.assign(existing, payload, { updated_at: this.now });
            created.push(existing);
            continue;
          }
        }
        this.assertUnique(table, row);
        this.table(table).push(row);
        created.push(row);
      }
      if (!wantsRepresentation) return route.fulfill({ status: 201 });
      return respondRows(route, this.embed(created, query.select ?? '*'), single, {}, 201);
    }

    if (method === 'PATCH') {
      const targets = applyFilters(this.visible(table), queryEntries);
      const patch = body as Row;
      if ('tenant_id' in patch && targets.some((t) => t.tenant_id !== patch.tenant_id)) {
        this.fail('new row violates row-level security policy', '42501', 403);
      }
      for (const row of targets) {
        const statusChanged = table === 'attendance_records' && 'status' in patch && patch.status !== row.status;
        Object.assign(row, patch, 'updated_at' in row ? { updated_at: this.now } : {}, statusChanged ? { recorded_by: this.session.userId } : {});
      }
      for (const row of targets) this.assertUnique(table, row, row);
      if (!wantsRepresentation) return route.fulfill({ status: 204 });
      return respondRows(route, this.embed(targets, query.select ?? '*'), single);
    }

    if (method === 'DELETE') {
      const targets = new Set(applyFilters(this.visible(table), queryEntries));
      this.deleteRows(table, targets);
      if (!wantsRepresentation) return route.fulfill({ status: 204 });
      return respondRows(route, [...targets], single);
    }

    return this.reportUnmocked(route, `${method} /rest/v1/${table}`);
  }

  /** Deletes rows and applies the schema's cascade / set-null rules to dependants. */
  /** A `restrict`/`no action` foreign key blocks the delete (23503), anywhere down the cascade. */
  private assertDeletable(table: string, targets: Set<Row>, seen = new Set<string>()): void {
    const ids = new Set([...targets].map((row) => row.id));
    for (const rule of ON_DELETE[table] ?? []) {
      const dependants = this.table(rule.child).filter((row) => ids.has(row[rule.column]));
      if (dependants.length === 0) continue;
      if (rule.action === 'restrict') {
        this.fail(`update or delete on table "${table}" violates foreign key constraint on table "${rule.child}"`, '23503', 409);
      }
      const key = `${rule.child}:${rule.column}`;
      if (rule.action === 'cascade' && !seen.has(key)) {
        seen.add(key);
        this.assertDeletable(rule.child, new Set(dependants), seen);
      }
    }
  }

  private deleteRows(table: string, targets: Set<Row>): void {
    this.assertDeletable(table, targets);
    const ids = new Set([...targets].map((row) => row.id));
    this.tables.set(
      table,
      this.table(table).filter((row) => !targets.has(row)),
    );
    for (const rule of ON_DELETE[table] ?? []) {
      const dependants = this.table(rule.child).filter((row) => ids.has(row[rule.column]));
      if (rule.action === 'set_null') {
        for (const row of dependants) row[rule.column] = null;
      } else if (dependants.length > 0) {
        this.deleteRows(rule.child, new Set(dependants));
      }
    }
  }

  private prepareInsert(table: string, payload: Row): Row {
    const row: Row = { ...payload };
    for (const [column, value] of Object.entries(COLUMN_DEFAULTS[table] ?? {})) {
      if (row[column] === undefined) row[column] = value;
    }
    for (const column of CURRENT_DATE_DEFAULTS[table] ?? []) {
      if (row[column] === undefined) row[column] = this.now.slice(0, 10);
    }
    for (const column of TABLE_COLUMNS[table] ?? []) {
      if (row[column] === undefined) row[column] = null;
    }
    if (this.session.role !== 'platform_administrator' && 'tenant_id' in row && table !== 'profiles') {
      if (row.tenant_id !== this.session.tenantId) {
        this.fail(`new row violates row-level security policy for table "${table}"`, '42501', 403);
      }
    }
    if (ACTOR_COLUMNS[table]) row[ACTOR_COLUMNS[table]] = this.session.userId;
    if (TABLE_COLUMNS[table]?.includes('id') && !row.id) row.id = this.newId();
    if (TABLE_COLUMNS[table]?.includes('created_at') && !row.created_at) row.created_at = this.now;
    if (TABLE_COLUMNS[table]?.includes('updated_at') && !row.updated_at) row.updated_at = this.now;
    return row;
  }

  private assertUnique(table: string, row: Row, self?: Row): void {
    for (const columns of UNIQUE_KEYS[table] ?? []) {
      const clash = this.table(table).find((other) => other !== self && other !== row && columns.every((c) => other[c] === row[c] && row[c] !== undefined));
      if (clash) this.fail(`duplicate key value violates unique constraint "${table}_${columns.join('_')}_key"`, '23505', 409);
    }
  }

  private embed(rows: Row[], select: string): Row[] {
    const embeds = embedsOf(select);
    if (embeds.length === 0) return rows;
    return rows.map((row) => {
      const out: Row = { ...row };
      for (const { alias, table } of embeds) {
        const fk = `${alias.replace(/s$/, '')}_id`;
        out[alias] = this.visible(table).find((target) => target.id === row[fk]) ?? null;
      }
      return out;
    });
  }

  // -------------------------------------------------------------------- RPC

  private async handleRpc(route: Route, request: Request, name: string): Promise<void> {
    const body = (parseBody(request) ?? {}) as Row;
    this.requests.push({ method: request.method(), path: `/rest/v1/rpc/${name}`, query: {}, body, rpc: name });
    const handler = this.rpcHandlers.get(name);
    if (!handler) return this.reportUnmocked(route, `RPC ${name} (no handler registered)`);
    const fault = this.takeFault(`rpc:${name}`, request.method());
    if (fault) return json(route, { message: fault.message, code: fault.code, details: null, hint: null }, fault.status);
    const result = await handler(body, this.context());
    return json(route, result === undefined ? null : result);
  }

  // ---------------------------------------------------------------- Storage

  private async handleStorage(route: Route, request: Request, path: string, origin: string): Promise<void> {
    const method = request.method();
    const sign = /^\/storage\/v1\/object\/sign\/([^/]+)\/(.+)$/.exec(path);
    if (sign && method === 'POST') {
      return json(route, { signedURL: `/object/sign/${sign[1]}/${sign[2]}?token=e2e-signed-token` });
    }
    if (sign && method === 'GET') {
      // Opening a signed URL (new tab): requires the token the signing step issued.
      if (new URL(request.url()).searchParams.get('token') !== 'e2e-signed-token') {
        return json(route, { message: 'Invalid token', statusCode: '400' }, 400);
      }
      return void (await route.fulfill({ status: 200, contentType: 'application/pdf', body: '%PDF-1.4 e2e' }));
    }
    const upload = /^\/storage\/v1\/object\/([^/]+)\/(.+)$/.exec(path);
    if (upload && (method === 'POST' || method === 'PUT')) {
      if (this.failUploads > 0) {
        this.failUploads -= 1;
        return json(route, { message: 'upload failed', error: 'InternalError', statusCode: '500' }, 500);
      }
      this.uploads.push({
        bucket: upload[1],
        path: decodeURIComponent(upload[2]),
        bytes: request.postDataBuffer()?.length ?? 0,
        contentType: request.headers()['content-type'] ?? null,
      });
      return json(route, { Id: this.newId(), Key: `${upload[1]}/${upload[2]}` });
    }
    void origin;
    return this.reportUnmocked(route, `${method} ${path}`);
  }

  // ------------------------------------------------------------------- Auth

  private async handleAuth(route: Route, request: Request, path: string): Promise<void> {
    const method = request.method();
    const body = parseBody(request);
    this.authCalls.push({ path, method, body });

    if (path === '/auth/v1/token' && method === 'POST') {
      const credentials = body as { email?: string; password?: string };
      const user = this.authUsers[(credentials.email ?? '').toLowerCase()];
      if (!user || user.password !== credentials.password) {
        return json(route, { error_code: 'invalid_credentials', msg: 'Invalid login credentials', code: 400 }, 400);
      }
      this.session = user.session;
      return json(route, authSession(user.session, this.now));
    }
    if (path === '/auth/v1/logout' && method === 'POST') return void (await route.fulfill({ status: 204 }));
    if (path === '/auth/v1/recover' && method === 'POST') {
      if (this.recoverRateLimited) {
        return json(route, { error_code: 'over_email_send_rate_limit', msg: 'Email rate limit exceeded', code: 429 }, 429);
      }
      return json(route, {});
    }
    if (path === '/auth/v1/resend' && method === 'POST') return json(route, {});
    const challenge = /^\/auth\/v1\/factors\/([^/]+)\/challenge$/.exec(path);
    if (challenge && method === 'POST') {
      return json(route, { id: `challenge-${challenge[1]}`, type: 'totp', expires_at: Math.floor(new Date(this.now).getTime() / 1000) + 300 });
    }
    const verify = /^\/auth\/v1\/factors\/([^/]+)\/verify$/.exec(path);
    if (verify && method === 'POST') {
      const submitted = (body as { code?: string } | undefined)?.code;
      if (submitted !== this.mfaCode) {
        return json(route, { error_code: 'mfa_verification_failed', msg: 'Invalid TOTP code entered', code: 400 }, 400);
      }
      this.session = { ...this.session, aal: 'aal2' };
      return json(route, authSession(this.session, this.now));
    }
    if (path === '/auth/v1/user' && method === 'PUT') {
      return json(route, authUser(this.session, this.now));
    }
    if (path === '/auth/v1/user' && method === 'GET') return json(route, authUser(this.session, this.now));
    return this.reportUnmocked(route, `${method} ${path}`);
  }
}

function parseBody(request: Request): unknown {
  const raw = request.postData();
  if (!raw) return undefined;
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

async function json(route: Route, body: unknown, status = 200, headers: Record<string, string> = {}): Promise<void> {
  await route.fulfill({ status, contentType: 'application/json', headers, body: JSON.stringify(body) });
}

async function respondRows(route: Route, rows: Row[], single: boolean, headers: Record<string, string> = {}, status = 200): Promise<void> {
  if (single) {
    if (rows.length !== 1) {
      return json(
        route,
        {
          code: 'PGRST116',
          details: `The result contains ${rows.length} rows`,
          hint: null,
          message: 'JSON object requested, multiple (or no) rows returned',
        },
        406,
      );
    }
    return json(route, rows[0], status, headers);
  }
  return json(route, rows, status, headers);
}

export function authUser(session: Session, now: string) {
  return {
    id: session.userId,
    aud: 'authenticated',
    role: 'authenticated',
    email: session.email,
    email_confirmed_at: now,
    phone: '',
    app_metadata: { provider: 'email', providers: ['email'], role: session.role, ...(session.tenantId ? { tenant_id: session.tenantId } : {}) },
    user_metadata: {},
    identities: [],
    factors: (session.factors ?? []).map((f) => ({ created_at: now, updated_at: now, ...f })),
    created_at: now,
    updated_at: now,
  };
}

/** An unsigned, decodable JWT (test only): auth-js reads `aal` from it to decide MFA state. */
export function fakeJwt(session: Session, now: string): string {
  const iat = Math.floor(new Date(now).getTime() / 1000);
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    sub: session.userId,
    aud: 'authenticated',
    role: 'authenticated',
    email: session.email,
    aal: session.aal ?? 'aal1',
    amr: [{ method: session.aal === 'aal2' ? 'totp' : 'password', timestamp: iat }],
    session_id: '00000000-0000-4000-8000-00ee00000001',
    iat,
    exp: iat + 86400,
    app_metadata: { role: session.role, ...(session.tenantId ? { tenant_id: session.tenantId } : {}) },
  })}.e2e-signature`;
}

export function authSession(session: Session, now: string) {
  return {
    access_token: fakeJwt(session, now),
    token_type: 'bearer',
    expires_in: 86400,
    expires_at: Math.floor(new Date(now).getTime() / 1000) + 86400,
    refresh_token: 'e2e-refresh-token',
    user: authUser(session, now),
  };
}
