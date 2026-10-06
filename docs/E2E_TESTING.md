# End-to-end testing

All Playwright specs run against **one** deterministic backend: `e2e/utils/fakeBackend.ts` (an in-memory model of the PostgREST, RPC, Storage and GoTrue endpoints the app uses) seeded from `e2e/utils/sebetsaFixtures.ts` (a cleaning company, *Brightway Facilities (Demo)*: two clients, three sites, ten personas, shifts, tasks, leave, documents, assets, an SLA…). RPC behaviour is mirrored in `e2e/utils/rpcHandlers.ts`.

## Rules the harness enforces (a violation fails the test)

- A request to the Supabase origin that the backend does not model → failure (`unmocked`). There is no catch-all that returns an empty success.
- A request that leaves `localhost` → blocked and failed. Nothing can reach a real Supabase project: the app is built with `http://localhost:54321` and a dummy anon key.
- An uncaught page exception → failure.
- The clock is fixed (`2026-09-21T06:00:00Z`) and the browser runs in UTC with `en-ZA`, so date logic is deterministic.
- Writes are validated before they are applied (unique keys, foreign-key delete actions, the shift-overlap exclusion, check constraints), so a refused statement changes nothing — like a transaction.

## Keeping the fake honest

- Column lists, literal defaults, unique keys and foreign-key delete rules in `e2e/utils/schemaDefaults.ts` are **generated** from the migrations (`scripts/generate-db-types.sh`); CI fails if they are stale.
- `tests/e2eBackendCoverage.test.ts` (Vitest) fails if the app calls a table or RPC the fake does not model, if the fake models a table that does not exist, or if a handler is dead.
- The fake does **not** replace the database tests: authorisation, RLS, triggers and separation of duties are proven in `supabase/rls-tests`, and the fake re-implements only enough of them to exercise the UI. Where the fake and the SQL disagree, the SQL is right.

## What is covered

Authentication (login, reset, activation, email verification, MFA), tenancy, every role's navigation and route guards, users and scopes, employees, org structure (regions, clients, sites, contracts, SLA, documents), teams, site assignments, scheduling and availability, attendance, leave, tasks (including creation), incidents, compliance, documents, assets (including maintenance), inventory, procurement, workforce development, reports and export, notifications and preferences, dashboards, an axe accessibility sweep of every page of eight roles (light) and two (dark), keyboard/focus behaviour, and phone-viewport layout for five roles.

## Running

```bash
npm run build && npx playwright test                 # whole suite (~8 min on 2 workers)
npx playwright test org-structure --reporter=line    # one area
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/path/to/chrome ...   # use a preinstalled Chromium
```

Playwright is configured with one retry in CI only, a 30 s per-test timeout and a 25-minute global timeout, so a hang fails clearly.

## Not covered

Real network behaviour, real Supabase Auth flows (email delivery, rate limits), real Storage, browsers other than Chromium, and performance under load.
