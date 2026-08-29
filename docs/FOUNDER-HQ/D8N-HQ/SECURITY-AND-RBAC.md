# D8N HQ — Security, RBAC, Audit & Privacy

Status: mixed — §1 is **CURRENT REALITY** (audited), §2 onward is
**TARGET ARCHITECTURE** (proposed, not decided, not built). This is the
most consequential document in the set: HQ concentrates administrative
power that today is deliberately kept narrow and brand-scoped, so every
proposal here is written to be reviewed, not assumed.

## 1. Current reality: what D8N's authorization model actually does

Audited directly (not inferred) from `domains/admin/moderator_context.rb`,
`app/models/admin_{user,role,assignment}.rb`, and ADR 0013:

- Authorization is **brand-scoped only.** There is no concept of a
  platform-wide/cross-brand admin anywhere in the codebase.
- Authorization is **role-name-blind.** `Admin::ModeratorContext.resolve`
  checks only: is there a kept, active `AdminUser` for this `User`, and a
  kept, active `AdminAssignment` for *this specific brand* — full stop.
  The `AdminRole.name` attached to that assignment (`"moderator"` today,
  the only role that exists — see Phase 1 of this plan) is never read by
  any authorization check. **Any admin role currently grants full
  moderation and enforcement power for its brand.** This is explicit and
  intentional per ADR 0013: "differentiated admin RBAC is deliberately
  deferred until more roles genuinely exist."
- Admins are not a separate identity system: an admin signs in as an
  ordinary `User` through the ordinary brand-scoped session (ADR 0007),
  and needs an active `BrandMembership` on that brand to do so at all
  (same code path as any member's login — `Identity::PasswordLogin`).
- **Admin MFA does not exist.** Confirmed still open in
  `D8N_NOW_NEXT_LATER.md` as a pre-launch gate: "admins can read
  reporter/reported identities + report content, so MFA must be enabled
  before real user data is exposed in a live beta. Not built."
- Audit exists, but is write-only and split across two models
  (`SecurityEvent`, `AuthAttempt`) with no admin read API over either
  (CURRENT-STATE.md §3).

**HQ makes every one of these facts more consequential, not less.**
A tool whose entire purpose is "see everything, act on everything, across
every brand, in one place" is exactly the tool that turns
"any admin role grants full power for its brand" and "no MFA" from
acceptable-at-beta-scale risks into the central risk of the whole
product. Nothing below may be read as already mitigating that — it is a
proposal, gated on explicit decisions.

## 2. The cross-brand problem (restated, made concrete)

D8N-HQ-PLAN.md's "All D8N" selector needs a mechanism to prove a given admin
is *actually* authorized across brands, not just conveniently signed in
to several. Two structurally different ways to get there, **neither
implemented, neither decided**:

**Option A — Fan-out, no new grant.** HQ's "All D8N" view is literally N
separate per-brand API calls, each independently authorized by the
existing `Admin::ModeratorContext` against that brand. An admin without
an active `AdminAssignment` on brand X simply gets nothing back for brand
X, silently, same as today. **Pro:** zero new authorization surface, zero
new attack surface, ships immediately using the exact security model that
already has an ADR behind it (0013). **Con:** doesn't scale past a
handful of brands/admins conceptually (an admin has to be individually
assigned to every brand to see "everything"), and doesn't answer "what
about someone who should legitimately see cross-brand rollups
(founder-level company metrics) without being separately assigned as a
moderator on every single brand."

**Option B — A real platform-level grant.** Introduce a genuine
cross-brand authorization concept (e.g. a `platform_scope` flag on
`AdminAssignment`, or a `brand_id: nil` sentinel meaning "all brands," or
a dedicated `PlatformAssignment` table) that `Admin::ModeratorContext` (or
a new `Admin::PlatformContext`) explicitly checks. **This is a real
authorization-architecture change and needs its own ADR**, reviewed with
the same rigor as ADR 0013, before any line of code implements it — it is
explicitly the kind of thing this planning task was told not to invent
("Do not introduce platform-wide authorization").

**Recommendation for V1: Option A only.** Company-wide scores/rollups
(Command Centre) are the one legitimate case for "see everything" without
per-brand assignment — solve that narrowly by having the rollup jobs
(ARCHITECTURE.md §2) run as a trusted background process with direct DB
access (not through the admin-authorization path at all, the same way
`db:seed` or a rake task already has full DB access today), and have the
Command Centre UI render *pre-aggregated, already-anonymized-to-the-
metric-level* numbers that carry no per-member PII. That sidesteps
needing Option B for the one place it seemed unavoidable. Any HQ feature
that needs to *drill down* into individual member data across brands
still requires Option A's per-brand grant, with no exceptions, until
Option B is deliberately decided.

## 3. Proposed eventual HQ permission model (not built — target only)

The product brief sketches a list like `hq.command.read`,
`hq.members.manage`, `hq.security.read`, etc. **Before adopting any of
these names, the actual current model was inspected** (§1) — the honest
conclusion is that a fine-grained permission-string model does not exist
today and jumping straight to ~13 granular permissions would be
building the exact `AdminPermission` machinery ADR 0013 explicitly
deferred, without the "more roles genuinely exist" justification that ADR
asked for.

**Recommended sequencing instead of inventing names now:**

1. HQ V1 ships using the *existing* mechanism unchanged:
   `AdminAssignment` + the existing `moderator` `AdminRole`, scoped
   per-brand, exactly as Phase 1/2 of this plan already established.
   Anyone who can moderate a brand today can use HQ's per-brand views for
   that brand. No new role, no new table.
2. The first time HQ needs a *real* distinction (e.g. "can view Member
   360 including safety history" vs. "can also suspend an account" vs.
   "can view infra/observability data" vs. "can view company-wide
   rollups") — which will likely be very early, given how much more HQ
   exposes than the current reports queue — **that is the trigger ADR
   0013 was waiting for.** Write a new ADR at that point defining the
   actual role set D8N needs (grounded in HQ's real usage, not a
   speculative list), and only then add `AdminRole` rows and make
   `Admin::ModeratorContext` (or its HQ-specific successor) read the role
   name.
3. Until that ADR exists, treat "has an active AdminAssignment on this
   brand" as "can see and do everything HQ exposes for this brand" — the
   same blast radius that already exists today, not a new one. This is
   why §1's "no MFA" gap becomes urgent: HQ should not ship broad,
   privileged surfaces to a role that isn't itself protected by MFA.

**Recommendation: admin MFA becomes a hard prerequisite for HQ shipping
anything beyond read-only, low-sensitivity views** (e.g. Command Centre's
aggregated, anonymized scores are fine pre-MFA; Member 360 raw identity
lookups, message content, or any suspend/enforce action from HQ should
gate on MFA existing). This is a restatement of the existing pre-launch
gate, not a new one — HQ just raises its priority.

## 4. Audit requirements

Every privileged HQ read or write must be answerable for: **WHO, WHAT,
WHEN, WHY, TARGET, BRAND, BEFORE, AFTER, IP/session** where applicable —
exactly the fields already present on `AccountEnforcement`
(`admin_user_id`, `reason`, `created_at`/`reverted_at`, `user_id`/
`brand_id`, implicit before/after via `reverted?`) and on the
`SecurityEvent`+`ModerationAudit` pattern already used for report
transitions. **This is not a new requirement — it is already this
codebase's convention for every admin write.** HQ's job is:

- **Reuse the existing pattern for every new HQ write path** — no HQ
  domain service should perform a privileged mutation without an
  accompanying `SecurityEvent` (or equivalent), exactly like
  `Admin::SuspendProfile`/`Admin::TransitionReport` already do.
- **Close the read-API gap** (CURRENT-STATE.md §3.5/#8.4/etc.): build one
  admin-facing, paginated, brand-scoped read endpoint over `SecurityEvent`
  + `AuthAttempt` before HQ ships anything that displays audit history —
  today this data is written correctly but genuinely unreadable outside
  Rails console, which is itself a minimum-necessary-access violation in
  the other direction (only console-access engineers can see it).
- **Sensitive reads may also require auditing** (per the product brief).
  Concretely: a Member 360 load that surfaces safety history should
  itself emit a `SecurityEvent` (`hq.member_360_viewed` or similar),
  exactly the way `Admin::ReportDetail` already audits viewing a report's
  full evidence today (`domains/admin/moderation_audit.rb`). This is a
  small, direct extension of an existing pattern, not new architecture.

## 5. PII and minimum-necessary-access

The product brief's rule, already partially embodied in this codebase and
carried forward unchanged: **moderators/operators get the minimum
sensitive information necessary for the authorized task.**

Concrete applications for HQ:

- **Message content.** `Message.body` is plaintext with genuinely zero
  admin read surface today (CURRENT-STATE.md #4.12/#5.8). Do not add a
  general "view any conversation" HQ page. If/when a specific report
  targets a `message`/`conversation` (ADR 0018 already supports this),
  the *existing* `Report.evidence` jsonb snapshot — captured once, at
  report time, immutable — is the correct amount of message content to
  show a moderator: the reported content and its immediate reviewed
  snapshot, not an open-ended scroll through someone's private
  conversation history. HQ's Trust & Safety views should render exactly
  that evidence, not build a new raw-conversation viewer.
- **Member 360.** Should default to operational/product state (profile
  completeness, activity counts, delivery status) with safety-history
  sections (reports, enforcement) visible to the same role that can view
  the reports queue today — not a new, broader grant than reports already
  carry.
- **Universal search.** Any result that resolves to a specific member
  (ARCHITECTURE.md §5) is gated by the same per-brand authorization as
  everything else — a search across "All D8N" (§2, Option A) simply
  returns nothing for brands the searching admin isn't assigned to.
- **Observability/APM data** (once adopted, ARCHITECTURE.md §4) —
  configure the vendor integration to scrub message content / free-text
  PII from captured error context before it ever leaves D8N's servers.
  This is a vendor-configuration decision to make at adoption time, not
  an HQ-side redaction problem to solve later.

## 6. Data retention

D8N already has a documented retention policy for the product itself
(`docs/operations/data-retention.md`, ADR 0014). HQ does not introduce a
new retention regime — it inherits: whatever is purged from the product
DB (e.g. R2 media on account closure) is also gone from any HQ view built
on that same DB. The one new retention question HQ introduces is for
**new HQ-only data** (analytics events, metric rollup snapshots, audit
reads) — recommend those follow the same soft-delete-first,
explicit-purge-later convention used everywhere else in this codebase
(`deleted_at` columns, no hard deletes without an explicit, audited
reason), scoped as part of whichever ticket first creates the
`AnalyticsEvent` table (ARCHITECTURE.md §3).

## 7. Known, carried-forward open architectural concern

Restated per this task's explicit instruction not to silently redesign
it: **normal brand login requires an active `BrandMembership`, and
`Admin::FounderBootstrap` (Phase 2 of this plan) therefore creates/uses
`BrandMembership` rows on brands the founder didn't originally join, so
that the resulting `AdminAssignment` is actually usable.** This is
consistent with — not a violation of — everything in this document
(it reuses `BrandMembership` exactly as designed, doesn't invent
anything), but it is a real coupling between "how do we log an admin
into a brand" and "how do we grant admin power on a brand" that the
eventual Option B (§2) cross-brand grant, if it's ever built, should
resolve more cleanly (a genuine platform-level admin arguably shouldn't
need a consumer-facing `BrandMembership` on every brand just to pass an
authorization check). Flagged for whoever writes that future ADR; not
resolved here.
