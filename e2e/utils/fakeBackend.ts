import type { Page, Request, Route } from '@playwright/test';

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

/** Unique constraints modelled from the schema (column sets per table). */
const UNIQUE_KEYS: Record<string, string[][]> = {
  employees: [['tenant_id', 'employee_number']],
  regions: [['tenant_id', 'name']],
  departments: [['tenant_id', 'name']],
  contracts: [['tenant_id', 'contract_number']],
  profiles: [['email']],
  team_members: [['team_id', 'employee_id']],
  leave_balances: [['tenant_id', 'employee_id', 'leave_type_id', 'period_year']],
  notification_preferences: [['profile_id']],
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

function applyFilters(rows: Row[], query: Record<string, string>): Row[] {
  let result = rows;
  for (const [key, raw] of Object.entries(query)) {
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
    return rows.filter((row) => !('tenant_id' in row) || row.tenant_id === this.session.tenantId);
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
    await page.route(`${supabaseOrigin}/**`, (route) => this.handle(route, supabaseOrigin));
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
    const query = Object.fromEntries(url.searchParams.entries());
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
      const matched = applyFilters(this.visible(table), query);
      const total = matched.length;
      let rows = applyOrder(matched, query.order);
      const offset = Number(query.offset ?? 0);
      if (offset) rows = rows.slice(offset);
      if (query.limit !== undefined) rows = rows.slice(0, Number(query.limit));
      const embedded = this.embed(rows, query.select ?? '*');
      const headers: Record<string, string> = {};
      if (wantsCount) headers['content-range'] = `${rows.length ? `${offset}-${offset + rows.length - 1}` : '*'}/${total}`;
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
      const targets = applyFilters(this.visible(table), query);
      const patch = body as Row;
      if ('tenant_id' in patch && targets.some((t) => t.tenant_id !== patch.tenant_id)) {
        this.fail('new row violates row-level security policy', '42501', 403);
      }
      for (const row of targets) Object.assign(row, patch, 'updated_at' in row ? { updated_at: this.now } : {});
      for (const row of targets) this.assertUnique(table, row, row);
      if (!wantsRepresentation) return route.fulfill({ status: 204 });
      return respondRows(route, this.embed(targets, query.select ?? '*'), single);
    }

    if (method === 'DELETE') {
      const targets = new Set(applyFilters(this.visible(table), query));
      this.tables.set(
        table,
        this.table(table).filter((row) => !targets.has(row)),
      );
      if (!wantsRepresentation) return route.fulfill({ status: 204 });
      return respondRows(route, [...targets], single);
    }

    return this.reportUnmocked(route, `${method} /rest/v1/${table}`);
  }

  private prepareInsert(table: string, payload: Row): Row {
    const row: Row = { ...payload };
    if (this.session.role !== 'platform_administrator' && 'tenant_id' in row && table !== 'profiles') {
      if (row.tenant_id !== this.session.tenantId) {
        this.fail(`new row violates row-level security policy for table "${table}"`, '42501', 403);
      }
    }
    if (!('id' in row) && table !== 'team_members' && table !== 'contract_sites') row.id = this.newId();
    if (!('created_at' in row)) row.created_at = this.now;
    if (!('updated_at' in row) && !['team_members', 'contract_sites', 'audit_log', 'notifications'].includes(table)) {
      row.updated_at = this.now;
    }
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
    factors: [],
    created_at: now,
    updated_at: now,
  };
}

export function authSession(session: Session, now: string) {
  return {
    access_token: 'e2e-access-token',
    token_type: 'bearer',
    expires_in: 86400,
    expires_at: Math.floor(new Date(now).getTime() / 1000) + 86400,
    refresh_token: 'e2e-refresh-token',
    user: authUser(session, now),
  };
}
