# Sebetsa Enterprise Delivery Status

**Rule:** one enterprise control is not marked complete until it is implemented, verified, tested, documented and safe to release.

Last reconciled: 2026-10-06.

## Current platform domains

- Workforce & employee management — CLOSED
- Organisation hierarchy — CLOSED
- Scheduling & availability — CLOSED
- Attendance — CLOSED
- Leave management — CLOSED
- Tasks & operational workflows — CLOSED
- Site operations — CLOSED
- Documents & employee records — CLOSED
- Compliance & incidents — CLOSED
- Procurement, inventory & assets — CLOSED
- Client contracts & SLA — CLOSED
- Performance, training & skills — CLOSED
- Reporting & management intelligence — CLOSED

## Enterprise hardening

- Repository identity purification — IN PROGRESS
- Production release gate — IMPLEMENTED
- Node/runtime modernization — IMPLEMENTED
- Notification outbox reliability — IMPLEMENTED IN SOURCE; LIVE WORKER VERIFICATION PENDING
- Security governance — IMPLEMENTED
- Demo dataset — IMPLEMENTED
- Branch protection — BLOCKED ON GITHUB INTEGRATION PERMISSION
- Live Supabase security certification — BLOCKED UNTIL SEBETSA PROJECT IS CONNECTED
- Production domain/secrets verification — BLOCKED UNTIL HOSTING CONFIGURATION IS PROVIDED
- BCDR restore test — PENDING LIVE ENVIRONMENT
- Scope-aware region/client/site authorization certification — PENDING LIVE TEST
- Enterprise observability certification — PENDING
- GPS/geofencing/tours/offline field layer — NEXT PRODUCT BUILD
- Command centre — NEXT PRODUCT BUILD

## Release definition

Sebetsa is not declared enterprise-certified until the remaining live controls above are verified in the actual production environment. Source code alone is insufficient evidence for hosted configuration, live database policy state, secrets, backups, branch protection or external provider behaviour.
