# Sebetsa Documentation

Sebetsa is an enterprise multi-tenant workforce and operations platform.

## Core engineering documents

- [Product scope](./PRODUCT_SCOPE.md)
- [Delivery status — what is verified, where](./DOMAIN_STATUS.md)
- [Enterprise readiness and release gates](./ENTERPRISE_READINESS.md)
- [Security model](./SECURITY_MODEL.md) and the [security policy](../SECURITY.md)
- [Notification delivery](./NOTIFICATIONS_DELIVERY.md)
- [End-to-end testing](./E2E_TESTING.md)
- [Business continuity and observability](./BCDR_OBSERVABILITY.md)
- [Roadmap and gap analysis](./ROADMAP.md)

## Platform backbone

Organisation → Region → Client → Site → Workforce

The platform covers workforce management, scheduling, attendance, tasks, site operations, documents, compliance, incidents, procurement, inventory, assets, contracts, SLAs, performance, training, skills and reporting.

## Security baseline

Database authorization is authoritative. Tenant-scoped data uses PostgreSQL RLS and FORCE RLS. Privileged state transitions use controlled server-side functions. Service-role credentials never belong in the browser.

## Release rule

A release is not complete because the UI builds. It must pass the gate chain in [ENTERPRISE_READINESS.md](./ENTERPRISE_READINESS.md): quality, edge functions, RLS, E2E, then the release gate.
