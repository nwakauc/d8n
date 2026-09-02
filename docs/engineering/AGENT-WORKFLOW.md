# D8N Engineering Workflow and Capability Lifecycle

## Scope

This workflow applies to Date9ja parity work and reusable D8N capability work. The migration program is coordinated through repository documentation, not chat history alone.

## Roles

- **Product owner:** owns product decisions and final approval of user-visible semantics. Git commits, pushes, and deployments remain with the product owner unless explicitly delegated.
- **Coordinator:** sequences work, reviews reports, identifies ambiguity, and maintains initiative-level planning with the product owner.
- **Builder:** owns one bounded capability, reads required context, implements assigned scope, tests, self-reviews, updates docs, and produces a handoff.
- **Independent reviewer:** attempts to disprove significant work without modifying it initially; checks architecture, security, authorization, tenancy, data integrity, API behavior, parity, tests, and documentation.

## Startup protocol

Before significant parity work, read: repository `AGENTS.md`/`AGENT_RULES.md`; migration `README.md`, `STATUS.md`, relevant `MASTER-PLAN.md` section, parity rows, acceptance criteria, and relevant architecture/ADR/domain docs. Inspect the Date9ja source repository for the capability being changed. Do not reread every document when routing links identify the relevant context.

## Ownership and collision prevention

`STATUS.md` is the current ownership record. Only one builder owns a capability at a time. The record must name capability, builder, reviewer, state, primary domain, and overlapping files. Parallel work is allowed only with non-overlapping files/domains and an agreed shared contract. No simultaneous edits to the same capability or contract without explicit coordination.

## Capability lifecycle

```text
IDENTIFIED → SPECIFIED → READY → IMPLEMENTING → IMPLEMENTED → SELF_VERIFIED
      → IN_REVIEW → VERIFIED → PARITY_ACCEPTED
                              ↘ CHANGES_REQUESTED → IMPLEMENTING
```

- **IDENTIFIED:** observed in source or target gap; ownership and evidence recorded.
- **SPECIFIED:** behavior, domain owner, policy boundary, data/API contract, risks, and acceptance journey documented.
- **READY:** dependencies, decisions, scope, and test plan are approved; builder may start.
- **IMPLEMENTING:** bounded work is actively owned; overlapping work is paused or coordinated.
- **IMPLEMENTED:** code and intended tests exist; this is not completion.
- **SELF_VERIFIED:** builder ran applicable checks and documented evidence/limitations.
- **IN_REVIEW:** independent reviewer is examining the implementation and evidence.
- **CHANGES_REQUESTED:** review found unresolved issues; builder may resume after scope is clear.
- **VERIFIED:** review findings are resolved and quality gates pass.
- **PARITY_ACCEPTED:** the relevant Date9ja user journey passes and product owner accepts any approved semantic differences.

Tests passing alone cannot advance a capability to `PARITY_ACCEPTED`.

## Handoff protocol

Use the template in `HANDOFF-TEMPLATE.md` for significant work. Include exact files, database/API changes, security, tests and results, Date9ja behavior exercised, parity status delta, known limitations, decisions, and reviewer focus. Tiny changes may be reported in the final response instead of archived.

## Review protocol

The reviewer first reads the diff and tests without changing implementation. Review is adversarial: attempt to find data loss, cross-brand access, bad public serialization, race conditions, contract drift, missing frontend paths, untested error behavior, and unnecessary Date9ja coupling. Builder cannot independently mark significant work `VERIFIED` or `PARITY_ACCEPTED`.
