# Sebetsa

Sebetsa is an enterprise, multi-tenant **workforce and operations platform for commercial cleaning and facilities-management businesses**.

> cleaning company → clients → contracts → sites → teams → employees → shifts → work → evidence → service performance

It answers one question for operations managers: *who is working, where are they assigned, what work is required, what was completed, what went wrong, who approved it, and how is each contract performing.* See [docs/PRODUCT_SCOPE.md](docs/PRODUCT_SCOPE.md).

## What is in the product

Workforce and employee records · organisation hierarchy (regions, clients, contracts, sites, teams) · site assignments and staffing requirements · scheduling, shift definitions and availability · attendance (clock in/out, corrections, rosters) · leave · tasks with checklists and evidence · incidents and corrective actions · compliance requirements and records · employee and contract documents · skills, qualifications, training and performance reviews · procurement, inventory and assets · client contracts and SLA measurement · in-app notifications with optional email/SMS/WhatsApp delivery · operational reports and CSV export.

Roles: platform administrator, organisation administrator, operations manager, regional manager, site manager, supervisor, HR, employee and client user. What each can see and do is defined in `src/features/rbac/constants/rolePermissions.ts` and — authoritatively — enforced in the database.

## Stack

- **Frontend:** React 18, TypeScript, Vite, React Router, React Hook Form + Zod, Tailwind CSS.
- **Backend:** Supabase — PostgreSQL (row-level security, `SECURITY DEFINER` RPCs), Auth (including TOTP MFA), Storage, one Edge Function (`notifications-dispatch`, Deno).
- **Quality:** Vitest, Playwright + axe-core, a PostgreSQL regression harness for RLS and triggers, Deno tests, GitHub Actions.

## Repository layout

| Path | Contents |
| ---- | -------- |
| `src/features/*` | One folder per product area (pages, components, hooks, services, schemas). |
| `src/lib/database.types.ts` | **Generated** from the migrations — do not edit (`scripts/generate-db-types.sh`). |
| `supabase/migrations` | The schema, policies, functions and audit/security controls. The single source of truth. |
| `supabase/rls-tests` | Database regression suites (`tests/*.test.sql`) and the harness that runs them. |
| `supabase/functions` | Edge Function(s) and their unit tests. |
| `supabase/seed.sql` | Small deterministic demo organisation for local use. No real people, no credentials. |
| `e2e` | Playwright specs. `e2e/utils/fakeBackend.ts` is the one deterministic backend they all run on. |
| `docs` | Product scope, readiness, security model, operations. Start at [docs/README.md](docs/README.md). |

## Getting started

```bash
npm ci
cp .env.example .env.local   # fill in the Supabase URL and anon key
npm run dev
```

For a local backend use the Supabase CLI (`supabase start`, then `supabase db reset` applies the migrations and `supabase/seed.sql`). The seed creates organisational data only — create your first user in the Supabase dashboard / Studio. Never point a development build at a production project, and never put a `service_role` key in any `VITE_` variable.

## Checks

| Command | What it proves |
| ------- | -------------- |
| `npm run typecheck` / `npm run lint` | Types and lint rules. |
| `npm run test` | Unit tests (pure, no network). |
| `npm run build` | The production bundle compiles. |
| `npm run test:e2e` | Every workflow in a real browser against the in-memory Sebetsa backend. Requests that the backend does not model, or that leave `localhost`, **fail the test**; nothing can reach a real Supabase project. Includes an axe accessibility sweep and phone-viewport checks. |
| `bash supabase/rls-tests/run.sh` | Applies every migration to a throwaway PostgreSQL and runs every RLS / trigger / `SECURITY DEFINER` / separation-of-duties suite. Needs Docker, or `RLS_DATABASE_URL` pointing at an empty disposable server (hosted URLs are refused). |
| `bash scripts/generate-db-types.sh --check` | The generated types and the E2E backend's schema tables match the migrations. |
| `deno test` in `supabase/functions` | Edge Function logic. |

## Continuous integration and release

`.github/workflows/ci.yml` runs a chain — **quality → edge functions → RLS → E2E → release gate → deploy** — where each job needs the one before it. Deploy happens only for a push to `main`, only after the release gate confirms every gate passed, and is the only job that reads secrets. Pull requests (including from forks) run the same gates with a read-only token and no secrets. See [docs/ENTERPRISE_READINESS.md](docs/ENTERPRISE_READINESS.md).

## Security model in one paragraph

Authorisation is decided by the database. Every tenant table has RLS **and** FORCE RLS; privileged transitions go through `SECURITY DEFINER` functions that pin `search_path`, check the caller, and are executable only by the roles that need them. Regional, client and site scope is enforced by restrictive policies (a scoped role with no scope assigned sees nothing). Approval workflows enforce separation of duties — a person cannot approve, verify or close a record they raised or that concerns them. Audit events are append-only and split into security and business categories. Service-role credentials exist only in Edge Functions. Details: [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md) and [SECURITY.md](SECURITY.md).

## Status

What is verified in the repository, in CI, and against a live environment is tracked honestly in [docs/DOMAIN_STATUS.md](docs/DOMAIN_STATUS.md). Hosted-environment controls (live RLS state, secrets, backups, branch protection, provider behaviour) cannot be proven from source and are listed there as such.
