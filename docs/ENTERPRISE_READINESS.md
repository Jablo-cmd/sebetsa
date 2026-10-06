# Sebetsa Enterprise Readiness

## Release gates

A production release is green only when all of the following pass on the release commit:

1. TypeScript typecheck
2. ESLint
3. Unit tests
4. Production build
5. Edge Function typecheck and lint
6. Payment provider adapter tests
7. RLS / trigger / SECURITY DEFINER regression tests
8. Playwright E2E
9. Production configuration validation
10. Dependency/security audit

Production deployment must run only from `main`, after all release gates pass.

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
