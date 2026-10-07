# Sebetsa delivery status

**Rule:** a control is not marked GREEN unless it passed. Evidence is labelled by *where* it was obtained, because they are not interchangeable:

- **Repo** — present in source and reviewed.
- **Local** — executed on a developer machine / harness (PostgreSQL 16 locally).
- **CI** — executed by GitHub Actions on the branch (`workflow_dispatch`, PostgreSQL 17 service).
- **Live** — verified against the hosted Supabase project, hosting and providers.
- **Blocked** — cannot be established without access this repository does not have.

Last reconciled: 2026-10-07. **CI run 123** (`workflow_dispatch` on the branch, commit `5ffd3be`, https://github.com/Jablo-cmd/sebetsa/actions/runs/37568931167): quality, edge functions, RLS (21 suites + two-session outbox concurrency test + generated-types check), E2E (328 tests) and release gate all green; deploy correctly skipped (not `main`). Earlier runs 120 and 121 were red on E2E (CI-only timing/popup issues, since fixed) and the release gate blocked them; run 122 was green on the previous commit. Nothing is verified against a live Supabase project.

## Product areas

| Area | Repo | Local | CI |
| ---- | ---- | ----- | -- |
| Workforce & employees | ✔ | E2E + RLS | E2E + RLS |
| Organisation structure (regions, clients, sites, contracts, teams, site assignments) | ✔ | E2E + RLS | E2E + RLS |
| Access scopes (region/site/team) with management UI | ✔ | E2E + RLS | E2E + RLS |
| Scheduling, shift definitions, availability | ✔ | E2E + RLS | E2E + RLS |
| Attendance & corrections | ✔ | E2E + RLS | E2E + RLS |
| Leave | ✔ | E2E + RLS | E2E + RLS |
| Tasks (incl. creation), checklists, evidence, verification | ✔ | E2E + RLS | E2E + RLS |
| Site operations | ✔ | E2E | E2E |
| Documents (employee, contract) | ✔ | E2E + RLS | E2E + RLS |
| Compliance & incidents | ✔ | E2E + RLS | E2E + RLS |
| Procurement, inventory, assets (incl. maintenance log) | ✔ | E2E + RLS | E2E + RLS |
| Contracts & SLA | ✔ | E2E + RLS | E2E + RLS |
| Skills, qualifications, training, performance | ✔ | E2E + RLS | E2E + RLS |
| Reports & CSV export, dashboards | ✔ | E2E | E2E |
| Notifications (in-app, preferences) | ✔ | E2E + RLS | E2E + RLS |
| External delivery (email/SMS/WhatsApp): producer trigger, outbox, worker logic | ✔ | RLS + Deno | RLS + Deno |
| Accessibility sweep, phone-viewport layout | ✔ | E2E | E2E |

## Platform controls

| Control | State |
| ------- | ----- |
| RLS + FORCE RLS on every table; no anon grants; definer functions pin `search_path` | Repo + Local + CI (catalogue suite) |
| Scope-aware authorisation (restrictive policies, fail closed) | Repo + Local + CI |
| Separation of duties (13 rules, guard triggers) | Repo + Local + CI |
| Immutable, categorised audit trail; retention rule defined | Repo + Local + CI. Purge not scheduled. |
| Deactivated accounts locked out in the database | Repo + Local + CI |
| Generated types and E2E schema match migrations | CI (`--check`) |
| CI chain with release gate, least privilege, deploy-only-from-main | Repo; run on a branch via CI. The deploy job itself has never run (needs `main` + secrets). |
| MFA enforced server-side | **Not implemented** (documented open risk) |
| External message delivery to real providers | **Blocked** — needs deployed function, schedule, provider credentials |
| Live RLS/grant state of the hosted project | **Blocked** — needs the live project |
| Backups, PITR, restore drill, RPO/RTO | **Blocked** |
| Branch protection / required checks | **Blocked** — GitHub integration permission |
| Production domain, secrets presence | **Blocked** — hosting configuration not provided; none is assumed |
| Frontend error reporting, uptime, alerting | **Absent** |
| GPS / geofencing / tours / offline | Not built (roadmap P3) |
| Command centre | Not built (roadmap P1) |

See [SECURITY_MODEL.md](./SECURITY_MODEL.md), [BCDR_OBSERVABILITY.md](./BCDR_OBSERVABILITY.md) and [ROADMAP.md](./ROADMAP.md).

## Release definition

Sebetsa is not declared enterprise-certified until the Blocked and Absent rows above are closed in the real environment. Source code alone cannot evidence hosted configuration, live policy state, secrets, backups, branch protection or provider behaviour.
