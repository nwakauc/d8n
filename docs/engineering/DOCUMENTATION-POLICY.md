# D8N Documentation Policy and Hygiene Audit

## Policy

Before creating a document, search existing documentation and identify its authority. One concern has one source of truth. Architecture is long-lived system truth; ADRs record durable decisions and rationale; initiative plans describe intended work; status records current execution truth; runbooks describe operations; acceptance specifications describe required behavior; handoffs transfer temporary implementation context.

Update before creating. Link related documents rather than copying large sections. Do not write transcripts or agent narration. Supersede historical decisions with a new ADR or explicit status rather than silently rewriting history. Keep indexes/navigation current. Sensitive data and secrets never belong in documentation.

## Authority map

| Concern | Authority |
|---|---|
| Platform architecture | `PLAN_OF_ACTION.md`, `docs/architecture/`, accepted `docs/adr/` |
| Date9ja program | `docs/migrations/date9ja-to-d8n/MASTER-PLAN.md` |
| Current execution truth | `docs/migrations/date9ja-to-d8n/STATUS.md` |
| Capability inventory/status | `CAPABILITY-PARITY.md` |
| Capability ordering | `PARITY-BUILD-PLAN.md` |
| User acceptance | `FEATURE-PARITY-ACCEPTANCE.md` |
| API compatibility | `API-COMPATIBILITY.md` plus canonical `docs/api/openapi.yaml` |
| Data/cutover operations | `RECONCILIATION.md`, `CUTOVER-RUNBOOK.md` |
| Product decisions | `DECISIONS.md` |
| Agent workflow/handoff/lifecycle | `docs/engineering/AGENT-WORKFLOW.md`, `HANDOFF-TEMPLATE.md` |
| Quality and evidence | `docs/engineering/QUALITY-GATES.md` |

## Hygiene findings

- No prior single Date9ja master plan or current status document existed; created them.
- No prior shared lifecycle, handoff, quality-gate, or documentation-policy authority existed; created a consolidated engineering set.
- Phase 0 documents contained “legacy-only can wait” language that contradicted the new parity principle. `AUDIT.md`, `README.md`, `RECONCILIATION.md`, `CUTOVER-RUNBOOK.md`, and `MIGRATION-MATRIX.md` now label that framing historical/superseded; source-to-target mapping remains preserved.
- `PARITY-BUILD-PLAN.md` previously described only four broad waves; it has been aligned to the master plan while remaining the detailed capability ordering document.
- Existing D8N architecture and ADR documents remain authoritative and were not duplicated or rewritten.
- The Date9ja repository contains product/readiness documents and no competing migration control plane; it remains the behavioral source, not D8N architecture authority.
- `docs/FOUNDER-HQ/` contains operational/company planning and is intentionally preserved outside this initiative's authority.

## Cleanup proposal

Do not delete documents now. The obsolete architecture workflow now points to the engineering workflow. Retain historical audit text and source-repository documents for traceability; review stale Phase 0 “defer” language outside this directory during the next repository-wide documentation pass.

## ADR rule

Create an ADR for a durable system-wide architecture decision, new shared domain boundary, security/privacy model, irreversible retention/deletion decision, or intentional cross-brand semantic rule. Do not create ADRs for ordinary implementation details, routine endpoint adapters, or temporary task sequencing. Link the ADR from the master plan and relevant contract.
