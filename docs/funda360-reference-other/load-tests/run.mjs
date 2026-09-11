#!/usr/bin/env node
// FND-QA-002: Load test against the seeded demo dataset.
//
// WHAT THIS IS: a concurrent-request load generator that signs in as
// several REAL seeded Auris Academy accounts (across roles — principal,
// class_teacher, finance_manager, admissions_officer, guardian) and
// repeatedly issues realistic PostgREST reads through the SAME anon-key +
// JWT path the real frontend uses, for a fixed duration under a
// configurable concurrency. It goes through RLS exactly as a real browser
// session would (no service-role key, no bypass) — this measures the real
// request path, not a synthetic pg_bench-style DB-only benchmark.
//
// WHAT THIS IS NOT: it does not simulate scale beyond what's already
// seeded (Auris Academy's own demo data — a few hundred learners/
// guardians, a couple thousand attendance rows) — "load test against the
// seeded demo dataset" per the Kanban wording, not a synthetic-data-
// generation exercise. If a future need arises to test at 10x/100x the
// current seed size, that is a separate, larger follow-up (seeding at
// scale has its own real cost/risk — not attempted here).
//
// SAFETY: hard-refuses to run against anything but a loopback Supabase
// URL (127.0.0.1/localhost) — see assertLocalTarget() — matching this
// project's standing rule to never touch the hosted instance.
//
// Usage: node supabase/load-tests/run.mjs [--concurrency=20] [--duration=30]

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');

function loadDotEnvLocal() {
  const envPath = path.join(repoRoot, '.env.local');
  const out = {};
  try {
    const raw = readFileSync(envPath, 'utf8');
    for (const line of raw.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq === -1) continue;
      out[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
    }
  } catch {
    // No .env.local — fall through to process.env / defaults below.
  }
  return out;
}

const dotenv = loadDotEnvLocal();
const SUPABASE_URL = process.env.VITE_SUPABASE_URL ?? dotenv.VITE_SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY ?? dotenv.VITE_SUPABASE_ANON_KEY;

function assertLocalTarget(url) {
  const host = new URL(url).hostname;
  if (host !== '127.0.0.1' && host !== 'localhost') {
    throw new Error(`Refusing to load-test a non-local Supabase URL (${url}). This tool only ever targets the local dev instance.`);
  }
}
assertLocalTarget(SUPABASE_URL);

if (!SUPABASE_ANON_KEY) {
  throw new Error('VITE_SUPABASE_ANON_KEY not found in the environment or .env.local.');
}

const DEMO_PASSWORD = 'Funda360!DEMO-ONLY-2026';

// Real seeded Auris Academy accounts spanning the roles that exercise
// meaningfully different RLS/query shapes — not a synthetic actor set.
const VIRTUAL_USERS = [
  { email: 'principal@auris.funda360.dev', role: 'principal' },
  { email: 'lisa.smith9@auris.funda360.dev', role: 'class_teacher' },
  { email: 'finance@auris.funda360.dev', role: 'finance_manager' },
  { email: 'admissions@auris.funda360.dev', role: 'admissions_officer' },
  { email: 'parent@auris.funda360.dev', role: 'guardian' },
];

function argValue(flag, fallback) {
  const arg = process.argv.find((a) => a.startsWith(`--${flag}=`));
  return arg ? Number(arg.split('=')[1]) : fallback;
}

const CONCURRENCY = argValue('concurrency', 20);
const DURATION_SECONDS = argValue('duration', 30);

// Scenarios mirror the shape of real service-layer queries (same tables,
// same school-scoping, comparable row limits) without importing app code
// directly — this script runs standalone via `node`, outside Vite's
// module graph. Each scenario is tagged with the roles it's realistic for
// (matching this schema's own RLS/permission shape); a virtual user only
// ever runs scenarios valid for its role, mirroring what that role could
// actually reach in the real app rather than a uniform random mix.
const SCENARIOS = [
  {
    name: 'list_learners',
    roles: ['principal', 'class_teacher', 'admissions_officer'],
    run: (client, schoolId) => client.from('learners').select('*').eq('school_id', schoolId).order('last_name').limit(50),
  },
  {
    name: 'attendance_recent',
    roles: ['principal', 'class_teacher'],
    run: (client, schoolId) =>
      client
        .from('attendance_records')
        .select('*')
        .eq('school_id', schoolId)
        .order('attendance_date', { ascending: false })
        .limit(100),
  },
  {
    name: 'fee_charges_overview',
    roles: ['principal', 'finance_manager'],
    run: (client, schoolId) => client.from('learner_fee_charges').select('*').eq('school_id', schoolId).limit(100),
  },
  {
    name: 'assessments_list',
    roles: ['principal', 'class_teacher'],
    run: (client, schoolId) => client.from('assessments').select('*').eq('school_id', schoolId).order('assessment_date', { ascending: false }).limit(50),
  },
  {
    name: 'timetable_entries',
    roles: ['principal', 'class_teacher', 'admissions_officer'],
    run: (client, schoolId) => client.from('timetable_entries').select('*').eq('school_id', schoolId).limit(100),
  },
  {
    name: 'announcements_recent',
    roles: ['principal', 'class_teacher', 'finance_manager', 'admissions_officer', 'guardian'],
    run: (client, schoolId) => client.from('announcements').select('*').eq('school_id', schoolId).order('created_at', { ascending: false }).limit(20),
  },
  {
    name: 'my_children',
    roles: ['guardian'],
    run: (client) => client.from('learner_guardians').select('*, learners(*)').eq('active', true),
  },
];

function percentile(sortedMs, p) {
  if (sortedMs.length === 0) return 0;
  const idx = Math.min(sortedMs.length - 1, Math.ceil((p / 100) * sortedMs.length) - 1);
  return sortedMs[Math.max(0, idx)];
}

async function signIn(email) {
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data, error } = await client.auth.signInWithPassword({ email, password: DEMO_PASSWORD });
  if (error) throw new Error(`Sign-in failed for ${email}: ${error.message}`);
  const tenantId = data.user?.app_metadata?.tenant_id;
  if (!tenantId) throw new Error(`No tenant_id in app_metadata for ${email} — cannot scope scenario queries.`);
  return { client, schoolId: tenantId };
}

async function runVirtualUser(user, results, stopAt) {
  const { client, schoolId } = await signIn(user.email);
  const eligible = SCENARIOS.filter((s) => s.roles.includes(user.role));

  while (Date.now() < stopAt) {
    const scenario = eligible[Math.floor(Math.random() * eligible.length)];
    const startedAt = performance.now();
    let ok = true;
    try {
      const { error } = await scenario.run(client, schoolId);
      if (error) ok = false;
    } catch {
      ok = false;
    }
    const elapsedMs = performance.now() - startedAt;

    if (!results.has(scenario.name)) results.set(scenario.name, { samples: [], errors: 0 });
    const bucket = results.get(scenario.name);
    bucket.samples.push(elapsedMs);
    if (!ok) bucket.errors += 1;
  }
}

async function main() {
  console.log(`FND-QA-002 load test — target: ${SUPABASE_URL}`);
  console.log(`concurrency: ${CONCURRENCY} virtual users, duration: ${DURATION_SECONDS}s\n`);

  const results = new Map();
  const stopAt = Date.now() + DURATION_SECONDS * 1000;

  const workers = [];
  for (let i = 0; i < CONCURRENCY; i++) {
    const user = VIRTUAL_USERS[i % VIRTUAL_USERS.length];
    workers.push(runVirtualUser(user, results, stopAt));
  }

  await Promise.all(workers);

  const rows = [];
  let totalRequests = 0;
  let totalErrors = 0;
  for (const [name, bucket] of results) {
    const sorted = [...bucket.samples].sort((a, b) => a - b);
    const count = sorted.length;
    totalRequests += count;
    totalErrors += bucket.errors;
    rows.push({
      scenario: name,
      count,
      errors: bucket.errors,
      avgMs: sorted.reduce((a, b) => a + b, 0) / count,
      p50Ms: percentile(sorted, 50),
      p95Ms: percentile(sorted, 95),
      p99Ms: percentile(sorted, 99),
      maxMs: sorted[sorted.length - 1] ?? 0,
    });
  }
  rows.sort((a, b) => b.count - a.count);

  console.log('scenario'.padEnd(24), 'count'.padStart(7), 'errors'.padStart(7), 'avg(ms)'.padStart(9), 'p50(ms)'.padStart(9), 'p95(ms)'.padStart(9), 'p99(ms)'.padStart(9), 'max(ms)'.padStart(9));
  for (const r of rows) {
    console.log(
      r.scenario.padEnd(24),
      String(r.count).padStart(7),
      String(r.errors).padStart(7),
      r.avgMs.toFixed(1).padStart(9),
      r.p50Ms.toFixed(1).padStart(9),
      r.p95Ms.toFixed(1).padStart(9),
      r.p99Ms.toFixed(1).padStart(9),
      r.maxMs.toFixed(1).padStart(9),
    );
  }
  console.log(`\ntotal requests: ${totalRequests}, total errors: ${totalErrors} (${((totalErrors / totalRequests) * 100).toFixed(2)}%)`);

  process.exitCode = totalErrors > 0 ? 1 : 0;
}

await main();
