# Phase 1 Capability Parity Audit

## Current Date9ja architecture

Date9ja is a Rails 8 API application under `/Users/uchechinwaka/pro/Date9ja/api`, with separate React web and Expo/React Native mobile clients. The API uses PostgreSQL, Devise 5.0.4, `devise-jwt` 0.13.0, Active Storage, and Cloudflare R2 via the S3 adapter in production. The legacy model makes `User` the account, public dating profile, and relationship participant. Most product state is stored as columns on `users`; dating records reference user IDs directly.

The source has 39 tables, including core dating, trust/verification, notifications, Active Storage, community, Dating Hub, Aunty Phobie, company/admin, analytics-like audit, and operational records. It has no brand tenant boundary.

Important source behavior:

- Email/password authentication is Devise database authentication plus JWT dispatch/revocation.
- Email confirmation is Devise confirmable; phone verification is a custom `phone_verifications` flow.
- Profiles are largely `users` columns; photos are `photos` plus Active Storage attachments.
- Likes, passes, matches, messages, blocks, reports, notifications, push tokens, and profile views point directly to users.
- Match pairs are canonicalized by numeric user ID. Messages are ordered by `created_at`; read state is a message `read_at` timestamp.
- Admin/moderation, RealMe/selfie/video/government-ID records, trust score, community, Dating Hub, Aunty Phobie, monetization, and support-chat records are active source surfaces that must be parity-scoped; they are not automatically disposable migration data.

## Current D8N target architecture

D8N is one Rails API-only modular monolith with PostgreSQL. `Brand` is the tenant, `User` is platform identity, and `BrandMembership` plus `Profile` represent a Date9ja presence. Brand-owned activity references profiles: likes, passes, matches, conversations, messages, blocks, reports, locations, photos, notifications, devices, and preferences all carry `brand_id` and are checked for same-brand ownership.

Authentication is modeled as `IdentityIdentifier` → `Credential` → `CredentialPasswordHash`, with a separate brand-scoped `Session`. D8N uses bcrypt availability, HMAC-digested opaque session tokens, explicit host-based brand resolution, and soft deletion. D8N media uses `ProfilePhoto` and `MessageAttachment`; profile media is private and processed through D8N's media pipeline.

Current registered brand contracts are HookUs and DateZA. There is no `date9ja` installer or registry entry in the audited D8N tree. Provisioning Date9ja therefore requires a small brand-specific contract/installer addition before data import; it must not be implemented as scattered Date9ja conditionals.

## Main mismatch and relationship chain

The importer must create mappings in dependency order:

`legacy user → D8N user → date9ja membership/profile → profile options/preferences/location/photos → profile relationships → match → conversation/participants → messages/attachments → notifications/devices`

The source's user IDs must never be used as D8N primary keys by assumption. Preserve them in a restricted, unique external identity map, for example a migration-owned table or a D8N-supported legacy-reference record. The map must include source system, entity type, source ID, destination ID, source fingerprint/version, and importer version. Every phase must use `find-or-create` semantics under database uniqueness constraints.

## Identity and tenant risks

- A source user can have only one profile, while D8N permits one profile per brand; import must create exactly one `date9ja` membership/profile per eligible source user.
- Source relationships can accidentally become cross-brand if imported before both profiles are resolved. Every relationship row must verify both profiles belong to the Date9ja brand.
- Source `profile_hidden`, suspension, ban, deletion, and confirmation states do not map one-for-one to D8N membership/profile status and publication. Explicit state mapping is required.
- Existing source IDs, public IDs, and email addresses must not be treated as interchangeable identifiers.
- Source JWTs, JTI revocation state, and Action Cable query-token sessions are not D8N sessions.

## Changed migration principle

The Phase 0 “legacy-only can wait” classification is superseded. A capability may be deferred only if it is proven unused, explicitly removed by product decision, or retained through a supported legacy/read-only transition that users can still access. For a normal cutover, every active retained capability requires a D8N implementation, Date9ja policy, web/mobile API path, tests, and staging verification.

## Requested blocker classification

### MUST FIX BEFORE MIGRATION

- Approved snapshot access, source integrity report, and sensitive-data decisions.
- `date9ja` brand provisioning and complete target contract.
- Direct bcrypt verification proof and new D8N session issuance.
- Deterministic legacy-ID mapping with database uniqueness/idempotency.
- Complete mapping and feature parity for users, profiles, photos, profile video, likes, passes, matches, conversations, messages, reactions, views, verification, trust, notifications, Community, Dating Hub, Aunty Phobie, monetization, blocks, reports, and current moderation/deletion states.
- Safe media access/reference or copy plan, including broken-object detection.
- Delta/cutover and rollback procedure that prevents writes from being lost.

### SHOULD FIX DURING MIGRATION

- Move source profile data from overloaded user columns into D8N typed capabilities/options.
- Replace source opaque arrays with controlled option codes after value normalization review.
- Implement reusable verification/trust, engagement/profile-view, messaging/reactions, Community, AI, and PAY/Entitlements capabilities where required for active Date9ja behavior.
- Add analytics event backfill only if product reporting requires historical continuity.
- Add compatibility aliases/adapters for frontend contracts and deprecation telemetry.

### CAN WAIT UNTIL AFTER MIGRATION

- Only proven unused/legacy administrative surfaces, unrelated founder tooling, and unrelated platform improvements.
- Legacy schema cleanup, binary optimization, and frontend redesign.

## Phased strategy

| Phase | Work / validation / exit |
|---|---|
| 0 Audit | Classify every source table, obtain snapshot/data decisions, and approve blockers. Exit: reviewed field matrix. |
| 1 Provision | Add idempotent Date9ja installer/contract, trusted hosts, Nigerian locations, auth/profile/notification policy. Exit: host and tenancy tests pass. |
| 2 Gaps | Implement every missing/partial retained capability as a reusable D8N domain with Date9ja policy. Exit: all retained domains have targets. |
| 3 Tooling | Build dependency-ordered, checkpointed, dry-run importer with external-ID map, retries, quarantine, and reconciliation. Exit: repeated fixture imports are unchanged. |
| 4 Staging | Restore approved snapshot into isolated staging and import. Exit: counts, graph, auth, and media checks pass. |
| 5 Test | Run complete web/mobile feature journeys, moderation, notifications, realtime, and full reconciliation. Exit: no unexplained loss/orphans/duplicates and no unapproved feature gaps. |
| 6 Cutover | Freeze writes, final backup/delta, reconcile, switch trusted routing, smoke test, reopen. Exit: critical journeys green. |
| 7 Observe | Monitor auth, errors, messages, media, reports, and reconciliation. Exit: agreed stability period. |
| 8 Retire | Archive legacy backups/runbooks and retire only after legal/rollback approval. Exit: written approval; never delete during cutover. |
