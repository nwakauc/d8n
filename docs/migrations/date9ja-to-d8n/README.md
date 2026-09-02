# Date9ja → D8N Production Migration

Phase 0 audit and Phase 1.0 control-plane documentation only. Audited/remediated 2026-09-02. No production database, application code, configuration, media objects, or migrations were changed.

## Executive decision

Migration is feasible, but it is **HIGH complexity** for a small dataset because the source is a live, single-tenant, `User`-centric Devise application and D8N is a brand-tenant platform that separates `User` identity from `Profile` dating presence. The smallest safe path is an additive importer with an explicit legacy-ID map, a Date9ja brand contract, a compatibility/API adapter period, and a frozen cutover with reconciliation.

The source password hashes are expected to be directly reusable: Date9ja uses Devise database authentication with bcrypt and `encrypted_password`; D8N has bcrypt available and stores a password hash in `credential_password_hashes`. This must be proven against a sanitized snapshot before approval. Source JWTs and sessions are not reusable because D8N sessions are brand-scoped opaque-token sessions. Users should re-authenticate once after cutover; passwords should not be reset.

**Full retained Date9ja feature parity is a production cutover requirement.** No active Date9ja capability may become disabled, missing, or “Coming soon” because of this migration.

## Documents

- [AUDIT.md](AUDIT.md) — architecture, findings, scope, and risks
- [MIGRATION-MATRIX.md](MIGRATION-MATRIX.md) — source-to-target mapping for every source table/domain
- [AUTHENTICATION.md](AUTHENTICATION.md) — password, identifier, session, and verification findings
- [BRAND-CONTRACT.md](BRAND-CONTRACT.md) — proposed `date9ja` configuration and policy boundary
- [API-COMPATIBILITY.md](API-COMPATIBILITY.md) — legacy frontend/API comparison and minimum client work
- [RECONCILIATION.md](RECONCILIATION.md) — count, integrity, media, and idempotency checks
- [CUTOVER-RUNBOOK.md](CUTOVER-RUNBOOK.md) — staged cutover and rollback procedure
- [CAPABILITY-PARITY.md](CAPABILITY-PARITY.md) — complete user-facing capability inventory and status matrix
- [FEATURE-PARITY-ACCEPTANCE.md](FEATURE-PARITY-ACCEPTANCE.md) — user-journey cutover gates
- [PARITY-BUILD-PLAN.md](PARITY-BUILD-PLAN.md) — shared-capability implementation waves
- [MASTER-PLAN.md](MASTER-PLAN.md) — sole authoritative program phases and phase exit criteria
- [STATUS.md](STATUS.md) — concise current execution truth
- [DECISIONS.md](DECISIONS.md) — product owner, engineering, and mixed decision queue

## Agent startup route

1. Read repository `AGENTS.md` and `AGENT_RULES.md`.
2. Read this README and [STATUS.md](STATUS.md).
3. Read the relevant [MASTER-PLAN.md](MASTER-PLAN.md) phase.
4. Read the relevant rows in [CAPABILITY-PARITY.md](CAPABILITY-PARITY.md), the matching acceptance journeys, and applicable architecture/ADR/domain documents.
5. Check [DECISIONS.md](DECISIONS.md), then record capability ownership in `STATUS.md` before implementation.

Shared workflow, lifecycle, handoff, quality, and documentation rules are in
[`docs/engineering/AGENT-WORKFLOW.md`](../../engineering/AGENT-WORKFLOW.md),
[`QUALITY-GATES.md`](../../engineering/QUALITY-GATES.md),
[`HANDOFF-TEMPLATE.md`](../../engineering/HANDOFF-TEMPLATE.md), and
[`DOCUMENTATION-POLICY.md`](../../engineering/DOCUMENTATION-POLICY.md).

## Non-negotiable gates

1. Obtain an approved, access-controlled production snapshot and data dictionary; no importer should be designed from guessed live values.
2. Approve mappings for sensitive fields (faith, ethnicity, tribe, genotype, denomination, preferred tribes, precise location, verification evidence) and retention treatment for any data not represented in the target.
3. Add the `date9ja` brand installer/contract and every missing/partial shared capability required for retained Date9ja behavior before importer/cutover.
4. Prove bcrypt compatibility and all relationship/media mappings in staging.
5. Keep the legacy system intact and read-only-capable through the rollback period.

The next implementation step is the exact Phase 1 slice named in `STATUS.md`; it must not begin until explicitly assigned. No parity capability implementation was performed in this control-plane remediation.

## Audit limitations

No production credentials or database connection was used. Consequently, this report contains no live row counts. Counts in [RECONCILIATION.md](RECONCILIATION.md) are required measurements to run against an approved snapshot, not invented results.
