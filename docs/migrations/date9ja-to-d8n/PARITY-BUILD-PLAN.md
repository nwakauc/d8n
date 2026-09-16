# Parity Build Plan

The program is dependency-ordered. `MASTER-PLAN.md` is the sole phase model and
owns initiative gates; this document owns detailed capability ordering within
those phases.
No missing capability should be implemented as an isolated Date9ja fork.

The current execution state is in `STATUS.md`. The capability matrix and
acceptance journeys are mandatory inputs before a capability reaches `READY`.

## Wave A — shared platform foundations

1. Provision `date9ja` as a first-class brand contract/catalog/policy: `Brands::Date9jaInstaller`, contract, provisioner/registry wiring, trusted host resolution, Nigerian location catalogue, and a non-sensitive profile catalogue skeleton. Test installer idempotency, host conflicts, brand resolution, tenant isolation, and capability gating. Sensitive fields remain excluded.
2. Add a reusable external identity mapping mechanism and importer contract.
3. Prove bcrypt hash compatibility; implement identifier/session transition and recovery.
4. Complete Date9ja profile capabilities, controlled options, conditional completion, lifecycle, and privacy serialization.
5. Complete shared media/profile-video architecture and source-object migration strategy.
6. Establish shared verification and trust records/status history sufficient to preserve existing badges and moderation decisions.
7. Establish PAY/Entitlements primitives before importing premium/founding state.

Exit: every retained identity/profile/media/verification/entitlement field has an approved target and testable contract.

## Wave B — core dating parity

1. Discovery/search/location/activity and limits.
2. Profile views and exposure accounting.
3. Profile-based likes, passes, super-likes, rewind, matches, and unmatch.
4. Conversations, participant read state, message migration, media messages, replies, edits/deletes.
5. Reactions, realtime messaging, typing/presence, blocks, reports, and moderation.
6. Notifications, preferences, delivery state, push devices, web/mobile realtime badges.

Exit: the normal Date9ja dating loop is behaviorally equivalent on both clients.

## Wave C — rich engagement parity

1. Reusable Engagement/Profile Views capability.
2. Reusable Messaging/Reactions capability.
3. Reusable Trust and Verification capability, including evidence retention boundaries.
4. Advanced notification plans and delivery/retry semantics.
5. Insights/analytics and attribution continuity where product reporting requires it.

Exit: extended dating signals and trust surfaces are available without legacy-only fallbacks.

## Wave D — extended Date9ja capabilities

1. Shared Community domain: content, votes/RSVPs, media, reports, moderation, notifications.
2. Shared Dating Hub/Engagement primitives: batches, contacts, notes, suggestions, persona, daily life.
3. D8N AI shared runtime and assistant contract; Aunty Phobie is a Date9ja configuration/personality/policy consuming it. Provider egress, privacy, credentials, and safety must be specified first.
4. Shared PAY/Entitlements plans, purchases, webhook idempotency, and limit enforcement.
5. Any inventory capability discovered during implementation.

Exit: every active Date9ja client route has a supported D8N path or is removed only by explicit product decision.

## Delivery and validation sequence

Each wave requires: contract/ADR review where needed, shared-domain implementation, Date9ja policy, migration mapping, web adapter, mobile adapter, unit/request/contract tests, user-journey tests, staging snapshot import, reconciliation, and rollback evidence. Build no importer for a domain until its target behavior and retention decision are approved.
