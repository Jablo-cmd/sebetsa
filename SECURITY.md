# Security Policy — Sebetsa

Sebetsa is an enterprise multi-tenant workforce and operations platform.

## Reporting vulnerabilities

Do not disclose suspected vulnerabilities in public issues. Report them privately to the repository maintainers with:
- affected component and environment
- reproducible steps or proof of concept
- security impact
- affected versions/commits
- suggested mitigation where known

Never include production credentials, tokens, personal information, or customer data in a report.

## Security boundaries

- Tenant isolation is enforced server-side with PostgreSQL RLS/Force RLS.
- Authorization must not rely on client-side route visibility.
- SECURITY DEFINER functions must pin `search_path`, perform explicit authorization, and have least-privilege EXECUTE grants.
- Service-role credentials are server-side only and must never be shipped to the browser.
- External webhooks must authenticate the provider, validate event identity, reject replays, and be idempotent.
- Background workers must claim work atomically and use bounded retries/dead-letter handling.
- Audit/security events must not contain secrets or sensitive authentication material.

## Production access

Production credentials and privileged database access are restricted to authorized maintainers. Secrets belong in the hosting/provider secret store, never in Git.

## Dependency and release security

Every production release must pass typecheck, lint, unit tests, Edge Function checks, RLS regression tests, and E2E tests. Production deployment is permitted only from the protected `main` branch after those gates pass.

Dependency changes must be reviewed for known vulnerabilities, license impact, runtime support, and lockfile integrity.

## Incident response

Security incidents must be contained first, followed by credential rotation, impact assessment, evidence preservation, customer notification where required, remediation, and a post-incident review.
