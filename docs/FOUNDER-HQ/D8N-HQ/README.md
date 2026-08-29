# D8N HQ — Documentation Index

D8N HQ is the proposed unified company command centre for D8N: one place
to understand company state, drill into why, and take action, across
every brand and every domain (growth, product, trust & safety,
engineering, platform/admin).

**Status as of 2026-08-29: ACTIVE DELIVERY. Phase 1 and Phase 2 backend
slices are built; their frontend work and slice acceptance remain outstanding.**
This folder is the canonical, reviewable plan for D8N HQ
specifically — not for the D8N platform/product as a whole. Nothing here
should be read as "already built" unless a document explicitly says so
and cites evidence (file path / route / test).

## Start here

**[D8N-HQ-PLAN.md](D8N-HQ-PLAN.md) is the canonical overview.** Read it
first, and read it alone if you only have five minutes — it is written so
a new engineer or founder can understand what D8N HQ is, why we're
building it, what exists today, what doesn't, how it should be
architected, and what ships first, without opening any other file.

**The other files below are deeper engineering detail**, each owned by
one topic, cross-referenced from the plan and from each other. Open them
when you need the underlying evidence, the exact schema, or the literal
ticket list — not before.

| File | Scope | When to open it |
| --- | --- | --- |
| **[D8N-HQ-PLAN.md](D8N-HQ-PLAN.md)** | Canonical, self-contained product + architecture plan | Always start here |
| [CURRENT-STATE.md](CURRENT-STATE.md) | The full repository capability audit — every HQ-relevant domain, classified READY/PARTIAL/MISSING/EXTERNAL/FUTURE/DO NOT REBUILD, with file-path evidence | When you need to verify a specific claim about what exists today, or find the exact file/route/model backing it |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The detailed target HQ architecture — layers, event system, observability integration, universal search, Member 360, marketplace health, deployment intelligence, performance/safety boundaries | When implementing a specific HQ subsystem and you need the full design reasoning, not just the summary |
| [METRICS.md](METRICS.md) | The metric semantic layer — registry pattern, canonical metric definitions, versioning policy | When defining or consuming any number HQ displays |
| [SECURITY-AND-RBAC.md](SECURITY-AND-RBAC.md) | Current D8N admin authorization reality, the eventual HQ permission model (not decided), audit requirements, PII/privacy boundaries | Before building anything that reads sensitive data or performs a privileged action from HQ |
| [ROADMAP.md](ROADMAP.md) | Dependency-ordered implementation phases, exact backend/frontend tickets for the first slice, deferred work, open founder decisions | When planning or picking up implementation work |
| [PHASE-1-IMPLEMENTATION.md](PHASE-1-IMPLEMENTATION.md) | **BUILT**, not planned: what actually shipped for Phase 1 (Member 360, HQ-101–107), file-by-file, with the authorization/isolation/privacy/performance review and frontend integration notes. The JSON contract itself lives in `docs/api/openapi.yaml` (tag `Hq`). | When integrating against the HQ backend, or verifying a claim about what's live today |
| [PHASE-2-IMPLEMENTATION.md](PHASE-2-IMPLEMENTATION.md) | **BACKEND BUILT; SLICE PARTIAL:** Trust & Safety overview, repeat-offender aggregation, brand-wide enforcement history, reuse of the existing report/evidence and moderation actions, plus the exact frontend handoff. | Before implementing or verifying the Phase 2 Trust & Safety frontend |

## Naming note

These documents are scoped to **D8N HQ specifically**, not the D8N
platform/product as a whole. If you're looking for the product/platform's
own architecture decisions (brand tenancy, auth, matching, messaging,
reporting), those live in `docs/adr/` and `docs/architecture/` one level
up, and are referenced from D8N-HQ-PLAN.md where relevant — they are not
duplicated here.

## Relationship to other documentation

This folder does not replace or duplicate:

- **`docs/adr/`** — architecture decision records for the product backend
  itself. HQ reads and correlates that system; it doesn't redecide it
  here. Where HQ needs a new ADR-worthy decision (e.g. changing admin
  authorization for cross-brand access), this plan says so explicitly
  rather than deciding it inline — see SECURITY-AND-RBAC.md §2.
- **`docs/architecture/`, `docs/operations/`** — how the product backend
  and its infrastructure actually work today. CURRENT-STATE.md cites
  these rather than re-deriving them.
- **`docs/FOUNDER-HQ/D8N_FOUNDER_STATE.md`** and
  **`docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md`** — the founder's operational
  state file and one-screen product critical path, one directory up.
  These describe the **product** build (HookUs beta loop), not HQ, and
  are historical operational record — not superseded by this plan.
- **`/Users/uchechinwaka/pro/d8n/PLAN_OF_ACTION.md`** — the original
  whole-platform founding plan. Its "Phase 10: D8N Admin" section is the
  earliest version of this idea; D8N-HQ-PLAN.md §8 reconciles what from
  that plan is still correct, what shipped in a different (simpler)
  shape, and what was never built.
- **`docs/FOUNDER-HQ/DATEZA-BACKEND-PRODUCTION-AUDIT.md`** — a prior
  point-in-time backend audit of DateZA specifically. CURRENT-STATE.md is
  a fresh, HQ-scoped audit across both brands and is the one to trust
  going forward for HQ purposes.

## Non-goals of this planning pass

This plan does not build: HQ UI, dashboard endpoints, an observability
vendor integration, OpenTelemetry instrumentation, the analytics event
pipeline, Company Intelligence, anomaly detection, a redesign of D8N
authentication, or platform-wide founder authorization. See
[ROADMAP.md](ROADMAP.md) for what phase each of these belongs to.
