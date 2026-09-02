# Date9ja → D8N Capability Parity Master Plan

## Authority and objective

This is the sole authoritative phase model for moving the live Date9ja product onto D8N without reducing retained user-facing capability. It is subordinate to D8N architecture documents and accepted ADRs, and is complemented by `CAPABILITY-PARITY.md` (what must work), `PARITY-BUILD-PLAN.md` (detailed sequencing within these phases), `STATUS.md` (current truth), and `FEATURE-PARITY-ACCEPTANCE.md` (acceptance gates).

Date9ja is a D8N brand, not a second platform. Missing capability must first become a reusable D8N domain/service/model/API primitive, then be enabled through Date9ja policy, catalogue, limits, entitlements, or personality. No active Date9ja capability may become unavailable or “Coming soon” because of migration.

## Program status

- Phase 0 — Discovery & Audit: **COMPLETE**
- Phase 1.0 — Engineering Control Plane: **COMPLETE**
- All implementation phases: **NOT STARTED**
- Production cutover: **BLOCKED** until data parity and feature parity both pass

## Phases, dependencies, and exit criteria

### Phase 0 — Discovery & Audit — COMPLETE

Outputs: schema/domain audit, normalized capability inventory, web/mobile endpoint inventory, authentication/media findings, migration matrix, reconciliation and cutover plans. The authoritative current inventory and totals are in `CAPABILITY-PARITY.md`.

Exit: source and target are understood; every known capability is classified; no production access or mutation was needed.

### Phase 1.0 — Engineering Control Plane — CURRENT

Outputs: this master plan, `STATUS.md`, capability lifecycle, workflow/roles/ownership rules, handoff template, Definition of Done, layered quality gates, documentation policy/hygiene proposal, product decision queue, and aligned parity build plan.

Exit: the Phase 1.0 checklist below passes and a new agent can determine program state from repository documentation alone.

Authoritative exit checklist:

- [x] Master plan and sole phase authority exists
- [x] Concise status/project memory exists
- [x] Capability lifecycle and role-based workflow defined
- [x] Ownership/collision prevention and handoff protocol defined
- [x] Definition of Done and layered quality gates defined
- [x] Documentation policy and hygiene findings recorded
- [x] Product/engineering/mixed decision queue established
- [x] Capability matrix normalized and build plan aligned
- [x] AI shared-platform ownership and data-egress specification gate recorded
- [x] Platform reuse-remediation dependencies recorded
- [x] Cold-start audit completed

### Phase 1 — Shared Platform Foundations — NOT STARTED

Depends on Phase 1.0 and product decisions that affect identity, verification, media, and entitlements. Brand provisioning is independently buildable once its contract is specified; it does not wait for all profile/discovery remediation.

Required reuse-remediation dependencies from `docs/plans/D8N_PLATFORM_CAPABILITY_ARCHITECTURE_REMEDIATION_PHASE_1_PLAN.md`:

1. **Before brand provisioning:** confirm the authoritative brand capability contract/registry and resolver boundaries so `date9ja` can be installed without duplicating HookUs/DateZA behavior.
2. **Before writable Date9ja profiles:** complete brand-scoped profile field write enforcement, configuration-derived serialization, and non-sensitive Date9ja catalogue composition. This blocks profile onboarding/editing, profile completion, sensitive-field handling, photos/publication policy integration, and profile API parity; it does not block registering the brand record/contract.
3. **Before Date9ja discovery/discovery writes:** complete brand-owned discovery surface/policy resolution, remove HookUs assumptions from generic eligibility/status/filter code, and define Date9ja location/ranking semantics. This blocks discovery, search, recommendations, activity, likes/passes where eligibility depends on discovery, and profile-view exposure accounting.

Evidence for these dependencies is present in `app/controllers/api/v1/profile_controller.rb` and `profile_preferences_controller.rb` (brand-scoped persistence exists, but the writable contract is derived from generic field policy), `domains/profiles/configuration.rb` (fallback field exposure), `domains/matching/strategy_registry.rb` (brand surface resolution), and `domains/matching/eligibility_scope.rb` (shared eligibility assumptions). The remediation plan remains implementation work for a later assigned slice; no remediation code is part of Phase 1.0.

Implement: Date9ja brand contract/provisioning; reusable legacy identity mapping; bcrypt/session transition; Date9ja profile catalogue and completion policy; shared media/profile-video foundations; verification/trust foundations; PAY/Entitlements foundations where required by retained behavior.

Exit: every retained foundation capability has an approved owner, contract, Date9ja policy, migration mapping, tests, and no unresolved security/privacy blocker.

### Phase 2 — Core Dating Capability Parity — NOT STARTED

Depends on brand/profile/identity foundations.

Implement: discovery/search/location/activity/limits; profile views; likes, passes, rewind, matches; conversations, messages, read state, media, replies, edits/deletes; reactions; blocks/reports; notifications; realtime/presence/typing where source behavior requires it.

Exit: the complete normal Date9ja dating loop passes web and mobile acceptance journeys against a migrated staging snapshot.

### Phase 3 — Trust, Rich Media & Engagement — NOT STARTED

Depends on Media, Verification, Trust, Messaging, and Engagement contracts.

Implement: profile video; advanced verification and history; verification badges; Trust XP/reputation; profile views and engagement; advanced notification delivery and presentation.

Exit: retained trust, verification, rich-media, and engagement behavior is available with approved privacy and moderation semantics.

### Phase 4 — Extended Shared Capabilities — NOT STARTED

Depends on the shared-domain ownership decisions from the parity matrix.

Implement: shared Community capability; Dating Hub primitives; D8N AI runtime plus a Date9ja Aunty Phobie assistant definition; PAY/Entitlements; support capability; remaining active capabilities. Community, Dating Hub, and Aunty Phobie remain in parity and cannot be silently dropped.

Exit: every retained Date9ja capability has a supported shared D8N target or an explicit product-approved replacement that preserves access and behavior.

### Phase 5 — Frontend/API Parity — NOT STARTED

Cross-cuts Phases 1–4; it is not repository topology restructuring.

Implement: web/mobile adapters, endpoint contracts, authentication transition, opaque-ID handling, onboarding configuration, uploads/private media, push, deep links, realtime, and all retained user journeys.

Exit: web and mobile clients run all retained Date9ja journeys against D8N with contract and regression evidence.

### Phase 6 — Migration Infrastructure — NOT STARTED

Can begin mapping/tooling design after Phase 1.0 and can proceed in parallel with capability implementation, but import execution depends on target contracts.

Implement: deterministic external-ID map; snapshot reader; dependency ordering; dry-run, checkpoint, retry, quarantine, idempotency; media migration; reconciliation output.

Exit: repeated/interrupted fixture imports produce no duplicates, no unexplained loss, and complete graph/media reconciliation.

### Phase 7 — Staging Rehearsal — NOT STARTED

Depends on Phases 1–6 and an approved sanitized production snapshot.

Run: isolated snapshot restore/import; migrated-account auth; complete data and feature parity; web/mobile, performance, security, failure, queue, notification, media, and realtime tests.

Exit: all mandatory checks pass with zero unexplained orphans, duplicates, data loss, or feature gaps.

### Phase 8 — Production Readiness — NOT STARTED

Depends on a successful staging rehearsal.

Prepare: rollback rehearsal; restorable backup; monitoring/alerts; queue and provider health; owners; communications; maintenance window; final-delta and freeze procedure.

Exit: signed readiness review and explicit product/technical approval.

### Phase 9 — Production Cutover — NOT STARTED

Depends on Phase 8 approval.

Freeze writes, back up, import final delta, reconcile, switch trusted routing, smoke test, and reopen only after both data and feature gates pass. Keep legacy Date9ja available and undeleted.

Exit: traffic is stable, critical journeys pass, monitoring is healthy, and rollback window is active.

### Phase 10 — Post-Cutover Verification — NOT STARTED

Verify authentication, discovery, engagement, messaging, media, notifications, verification, trust, Community, AI, payments/entitlements, queues, monitoring, and reconciliation.

Exit: agreed observation period passes without rollback triggers; only then may legacy retirement be separately considered.

## Cross-cutting gates

Every capability uses the lifecycle and gates in `docs/engineering/AGENT-WORKFLOW.md` and `docs/engineering/QUALITY-GATES.md`. “IMPLEMENTED” and “tests pass” do not mean “PARITY_ACCEPTED”.

## Architecture/specification gates

The following must have an ADR or approved architecture specification before the capability reaches `IMPLEMENTING`: external legacy reference mapping; profile video / media boundary; Engagement/profile-view boundaries; verification evidence and retention; Community boundary; Dating Hub decomposition/ownership; D8N AI assistant contract and egress policy; Trust ledger/derived reputation; entitlement preservation; and genotype/sensitive-profile privacy architecture.

Accepted: ADR 0022 (external legacy reference map). Proposed, pending review: ADR 0023 (profile video as a shared Media capability), ADR 0024 (shared verification-evidence architecture), ADR 0025 (Trust ledger / derived reputation), ADR 0026 (entitlement preservation). ADRs 0024–0026 define architecture and migration mapping only; their *implementation* still waits on the ADR 0011 human gates and the open `DECISIONS.md` product rows. See `DECISIONS.md` for the active queue.
