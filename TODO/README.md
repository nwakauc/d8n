# D8N Private Beta TODO

This folder is the accountable execution tracker for the smallest responsible
HookUs private beta. It complements the architecture documents and ADRs; it does
not replace them or authorize architecture changes.

> **Reconciliation (2026-08-17):** The single authoritative NOW/NEXT/LATER view is
> [`docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md`](../docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md).
> The strict "milestones in order" gate below has in practice been superseded by
> **beta-loop-first** prioritization: Milestone 4/5 product features (blocking,
> reporting, discovery filters, safe media) shipped ahead of some Milestone 1–3
> operational items because they define the product. Milestones 1–3 items remain
> real beta blockers and stay open; they are now tracked as **NEXT** rather than a
> hard predecessor. The confirmed remaining P0 loop gaps are **DL-03 (messaging)**,
> **TS-03 (admin moderation)**, **TS-04 (suspend/ban)**, and **TS-06 (account
> deletion)**.

## Working Principle

D8N is a dating platform, not a bank. Build the simplest responsible
implementation for the current scale that protects user safety, privacy, tenant
isolation, data integrity, and production reliability without speculative
enterprise complexity.

Before adding scope, ask:

1. Does it address a demonstrated safety, privacy, correctness, or operational risk?
2. Is it necessary at the current product stage?
3. Is there a simpler responsible implementation?
4. Would postponing it create dangerous or expensive-to-reverse debt?
5. Can we name the evidence or scale threshold that would justify it later?

## Private Beta Gate

Complete these milestones in order unless an explicit dependency requires a
small overlap:

- [ ] [Milestone 1 — Make the build safe](01_make_the_build_safe.md)
- [ ] [Milestone 2 — Make deployment real](02_make_deployment_real.md)
- [ ] [Milestone 3 — Make identity sane](03_make_identity_sane.md)
- [ ] [Milestone 4 — Make dating safe enough](04_make_dating_safe_enough.md)
- [ ] [Milestone 5 — Finish the dating loop](05_finish_the_dating_loop.md)
- [ ] Run the controlled-beta load and operational rehearsal defined in Milestone 5.
- [ ] Record a final go/no-go review with every launch-blocking item closed or explicitly accepted by the founder/CTO.

The private beta is not ready because a percentage of tasks is complete. It is
ready only when every item marked **Beta blocker** in the milestone files has
verifiable completion evidence.

## Accountability Rules

- Every task has a stable ID, priority, owner, status, and evidence requirement.
- Allowed statuses are `Not started`, `In progress`, `Blocked`, `Done`, and `Deferred`.
- Set an owner before moving a task to `In progress`.
- `Blocked` requires the blocker and the person or decision needed to unblock it.
- `Done` requires links to the relevant implementation, tests, operational output,
  or approved decision. A class, route, configuration entry, or passing unit test
  by itself may not prove the complete workflow.
- Do not silently broaden a task. Create a new task or update the task description
  and explain why.
- High-risk implementation still requires the short plan mandated by
  `AGENTS.md` and `AGENT_RULES.md`.
- API changes must update `docs/api/openapi.yaml`, `docs/api/README.md`, request
  tests, and the OpenAPI contract test in the same change.
- At the end of each implementation session, update only the tasks whose status
  or evidence actually changed.

## Priority Definitions

- **P0** — Critical security, data-loss, or serious production risk.
- **P1** — Must be completed before private beta.
- **P2** — Important cleanup or early-production hardening.
- **P3** — Later improvement.
- **P4** — Valid idea that is intentionally not worth the complexity now.

## Explicitly Outside the Private-Beta Gate

See [Later, when justified](90_later_when_justified.md). In particular, do not
delay the beta for microservices, Kubernetes, enterprise RBAC, a formal appeals
product, ordinary-user MFA, realtime chat, or a large media platform unless new
evidence changes the risk.

