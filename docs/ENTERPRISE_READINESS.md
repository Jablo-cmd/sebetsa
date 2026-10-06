# Sebetsa Enterprise Readiness

## Release gates

`.github/workflows/ci.yml` is a chain — each job `needs` the one before, so a red gate stops everything after it:

1. **Quality** — typecheck, lint, unit tests (including the E2E-backend drift guard), production build, `npm audit --omit=dev --audit-level=high`.
2. **Edge functions** — `deno check`, `deno lint`, `deno test` (dispatcher logic).
3. **RLS** — every migration applied to an empty PostgreSQL 17, every suite in `supabase/rls-tests/tests` run, and `scripts/generate-db-types.sh --check` (generated types and E2E schema tables must match the migrations).
4. **E2E** — the full Playwright suite against the deterministic fake backend (no real Supabase project can be reached).
5. **Release gate** — verifies that gates 1–4 all succeeded; always runs, so a failure upstream is reported rather than skipped.
6. **Deploy** — only for a push to `main`, only after the release gate, the only job that reads secrets, with a configuration check and a bundle check (no service-role strings).

Controls on the pipeline itself: workflow-level `permissions: contents: read`; `persist-credentials: false` on checkout; per-job timeouts; no secrets for pull requests or forks (the workflow uses `pull_request`, never `pull_request_target`); no secret value is ever echoed; runs on `main` are never cancelled mid-deploy. Actions are pinned by major version tag (Dependabot keeps them current); pinning by commit SHA is listed in the roadmap.

## Runtime baseline

- Node.js: supported LTS
- Supabase Edge Functions: Deno 2
- PostgreSQL: managed Supabase PostgreSQL
- Browser client: anon/publishable Supabase key only
- Service-role credentials: Edge Functions/server-side only

## Reliability baseline

Background work uses:
- atomic row claiming
- leases and expiry
- bounded retries
- exponential backoff
- idempotency/provider message IDs
- dead-letter state
- structured operational metrics

## Data protection baseline

Tenant boundaries are enforced in PostgreSQL. Sensitive records require explicit RLS policies. Audit trails must be append-oriented and must never store credentials or authentication secrets.

## Enterprise authorization

Authorization must account for:
- organisation
- region
- client
- site
- workforce scope
- role and permission
- separation of duties

A UI permission check is never a substitute for server/database authorization.

## Disaster recovery

Before production certification, the live Supabase project must have documented and tested:
- backup/restore procedure
- RPO
- RTO
- credential compromise recovery
- migration failure recovery
- hosting/domain recovery
- provider outage procedure

## Certification rule

Source-code inspection alone does not certify the live production database, hosted authentication configuration, secrets, provider webhooks, backups, or branch protection. Those controls require live verification.
