import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { KNOWN_TABLES } from '../e2e/utils/fakeBackend';
import { defaultRpcHandlers } from '../e2e/utils/rpcHandlers';
import { TABLE_COLUMNS } from '../e2e/utils/schemaDefaults';

/**
 * Drift guard for the E2E backend. Every table and RPC the application calls
 * must be modelled by the fake backend (or deliberately listed below), and every
 * modelled table must exist in the schema. Otherwise an E2E run could pass while
 * a real call would hit something the tests never exercised — or the fake could
 * model a table the migrations no longer have.
 */

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) && name !== 'database.types.ts' ? [path] : [];
  });
}

const sources = sourceFiles('src').map((file) => readFileSync(file, 'utf8'));
const used = (pattern: RegExp) => new Set(sources.flatMap((text) => [...text.matchAll(pattern)].map((m) => m[1] as string)));

const tablesUsed = used(/\.from\('([a-z_]+)'\)/g);
const rpcsUsed = used(/\.rpc\(\s*'([a-z_]+)'/g);

/** Calls the application makes that no E2E workflow reaches (and that the fake therefore does not answer). */
const UNMODELLED_RPCS = new Set<string>([]);

describe('E2E backend coverage', () => {
  it('models every table the application reads or writes', () => {
    const missing = [...tablesUsed].filter((t) => !(KNOWN_TABLES as readonly string[]).includes(t)).sort();
    expect(missing, 'tables used by src/ but not modelled in e2e/utils/fakeBackend.ts').toEqual([]);
  });

  it('models every RPC the application calls', () => {
    const missing = [...rpcsUsed].filter((r) => !(r in defaultRpcHandlers) && !UNMODELLED_RPCS.has(r)).sort();
    expect(missing, 'RPCs used by src/ but with no handler in e2e/utils/rpcHandlers.ts').toEqual([]);
  });

  it('only models tables that exist in the schema', () => {
    const phantom = (KNOWN_TABLES as readonly string[]).filter((t) => !(t in TABLE_COLUMNS)).sort();
    expect(phantom, 'fake-backend tables with no matching table in supabase/migrations').toEqual([]);
  });

  it('has no handler for an RPC that the application never calls', () => {
    const dead = Object.keys(defaultRpcHandlers).filter((r) => !rpcsUsed.has(r)).sort();
    expect(dead, 'handlers in e2e/utils/rpcHandlers.ts that nothing calls (delete or use them)').toEqual([]);
  });
});
