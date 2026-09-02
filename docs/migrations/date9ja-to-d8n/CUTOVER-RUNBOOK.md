# Cutover Runbook

Future procedure only; not executed during Phase 1. Data reconciliation and feature-parity acceptance are both mandatory gates.

## Before and during the window

1. Announce a short maintenance/read-only period and freeze releases/config changes.
2. Confirm an encrypted, restorable legacy database backup and media inventory; confirm D8N routing, queues, providers, monitoring, and owners.
3. Restore/import the tested snapshot and confirm Phase 5 data reconciliation plus every journey in `FEATURE-PARITY-ACCEPTANCE.md` for web and mobile.
4. Stop legacy writes and mutating jobs. Record the final source transaction/time boundary.
5. Take the final backup and import the final delta using the external-ID map. Do not replay historical notifications or source sessions.
6. Run counts, graph, media, duplicate, and password-hash checks. Abort on critical failure.
7. Switch the trusted Date9ja API host to D8N; verify no other brand host maps to Date9ja.
8. Smoke test existing-user password login, `/me`, profile/photo/video, discovery/search/views, like/pass, existing match/conversation/message/read/reactions/media/realtime, verification/trust, notifications/push, Community, Dating Hub, Aunty Phobie, monetization/entitlements, block, report, logout, and recovery.
9. Reopen writes only after smoke tests and monitoring are green.

## Rollback triggers

Rollback for material account lockout, cross-brand exposure, any retained feature being unavailable, broken conversation access, message/reaction/view loss or order corruption, duplicate identity/relationship creation, inaccessible media, security/authentication failure, or unreconciled critical loss.

## Rollback

Record the D8N boundary, route traffic to the legacy backend, re-enable legacy writes only after the boundary is recorded, and verify legacy health. Preserve D8N data, logs, backups, and reconciliation artifacts; do not delete or overwrite them. Reconcile any mixed-period writes before another attempt.

The legacy database/backend remains intact, access-controlled, and read-only-capable throughout the agreed stability period. Retirement is a separately approved phase and never part of cutover.
