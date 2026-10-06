# Sebetsa Documentation

Sebetsa is an enterprise multi-tenant workforce and operations platform.

## Core engineering documents

- [Enterprise readiness](./ENTERPRISE_READINESS.md)
- [Security policy](../SECURITY.md)
- [Architecture and implementation notes](./)
- Domain specifications and runbooks maintained with the relevant feature area.

## Platform backbone

Organisation → Region → Client → Site → Workforce

The platform covers workforce management, scheduling, attendance, tasks, site operations, documents, compliance, incidents, procurement, inventory, assets, contracts, SLAs, performance, training, skills and reporting.

## Security baseline

Database authorization is authoritative. Tenant-scoped data uses PostgreSQL RLS and FORCE RLS. Privileged state transitions use controlled server-side functions. Service-role credentials never belong in the browser.

## Release rule

A release is not complete because the UI builds. It must pass typecheck, lint, unit tests, Edge Function checks, RLS regression tests, E2E, production configuration validation and dependency/security checks.

## Documentation integrity

Funda360 reference material that was intentionally retained for engineering-pattern comparison is clearly marked as reference material and must never be used as Sebetsa production configuration, deployment identity, authentication branding or database authority.
