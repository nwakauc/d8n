# Milestone 4 — Make Dating Safe Enough

Outcome: beta users can stop contact, report harm, receive a human review, and
have enforcement applied consistently. A formal appeals product and a security
operations organization are not beta requirements.

## Tasks

### TS-01 — Preserve and verify blocking across every user path

- Priority: P1
- Beta blocker: Yes
- Owner: Codex / Claude
- Status: In progress
- Work: Keep existing brand-scoped directional blocks and prove they prevent
  discovery, likes/passes, match access, conversation access, and future message
  sends in either direction where required.
- Evidence: Cross-endpoint request tests cover both block directions, existing
  matches/conversations, suspended/deleted participants, and tenant isolation.
- Evidence recorded (2026-08-17): Fully implemented and unit/request-tested.
  `ProfileBlock` (directional, soft-delete, partial-unique active-pair index,
  self-block check constraint), `Trust::BlockProfile/UnblockProfile`, central
  `Trust::BlockPolicy` (`exclude_profiles`/`exclude_matches`/`blocked_between?`)
  wired into `EligibilityScope` (discovery all modes, likes, passes), `MatchList`,
  `ConversationList`, and `MatchAccess`. Blocked-user management list shipped in
  `b02f4f4` (`GET /api/v1/blocks`). Block/report/enforcement tests green
  (`test/controllers/api/v1/profile_blocks_controller_test.rb`, model +
  concurrency tests). Message-send enforcement is deferred until DL-03 exists.
  Remaining before Done: the staging cross-endpoint proof folded into DL-04.

### TS-02 — Add bounded user reporting

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: In progress
- Work: Implement brand-scoped profile/photo/message reporting with bounded reason
  codes and optional bounded user context. Preserve only the evidence required for
  review; never copy private message content into generic logs or audit metadata.
- Evidence: Authorization, tenant-isolation, duplicate/abuse-limit, evidence-access,
  deletion interaction, and serialization tests pass.
- Evidence recorded (2026-08-17): **Profile** reporting shipped (`55454be`).
  `Report` (bounded reason enum, status lifecycle, note ≤2000, DB partial-unique
  one-open-report-per-pair, self-report check constraint), `Trust::ReportProfile`
  (idempotent, brand-isolated, independent of blocking/visibility, writes a
  `SecurityEvent` audit signal), `POST /api/v1/profiles/:id/report`, OpenAPI +
  request tests green. Remaining scope: **photo and message reporting** (message
  reporting is gated on DL-03), and moderator evidence-access which is TS-03. No
  private content is copied into logs/metadata (verified).

### TS-03 — Provide a minimal admin review queue

- Priority: P1
- Beta blocker: Yes
- Owner: Claude
- Status: In progress (IMPLEMENTED + TESTED; not yet STAGING-PROVEN)
- Work: Allow explicitly authorized D8N beta moderators to list and review reports
  for permitted brands and record a decision. Use a small permission model for the
  actual beta team; do not build enterprise RBAC or external-operator support now.
- Evidence: Admin authentication, brand authorization, sensitive-read auditing,
  decision auditing, and denial tests exist. Admin MFA is enabled before real user
  data is accessible.
- Evidence recorded (2026-08-17): `GET /api/v1/admin/reports`, `GET/PATCH
  /api/v1/admin/reports/:id`. Admin auth **reuses the existing session** — new
  `admin_users.user_id` link + `Admin::ModeratorContext` (active AdminUser + active
  AdminAssignment for the host-resolved brand); 401 unauth / 403 non-moderator.
  Brand isolation is inherent (brand from host; queue scoped to `Current.brand`;
  cross-brand → neutral `report_unavailable`). Queue is oldest-first, status-
  filtered, signed-cursor paginated, preloaded (no N+1). Lifecycle
  `Admin::TransitionReport` (open→reviewing|dismissed, reviewing→actioned|dismissed|
  open; terminal→409 conflict via row lock; disallowed→422); only `status`+`note`
  mutable (no mass-assignment). Decision provenance on the report
  (`reviewed_by`/`reviewed_at`/`resolution_note`) + immutable `SecurityEvent` audit
  for detail reads and transitions (no report content in metadata). 17 request
  tests incl. the full report→decision loop; OpenAPI documented; all gates green.
- **Decisions needing founder ack (see report):** (1) admins authenticate as a
  brand-member `User` linked to an `AdminUser` — no separate admin auth system;
  worth an ADR. (2) Any active admin assignment currently grants moderation (role
  differentiation deferred). (3) **Admin MFA is still NOT built** — it remains the
  documented pre-launch gate ("enabled before real user data is accessible") and is
  a launch blocker, not a code gap in this slice.
- Remaining before Done: admin MFA, and the staging moderation drill (DL-04/DL-06).

### TS-04 — Enforce suspend and ban decisions

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Support brand-level suspension/ban with reason, actor, and timestamps;
  revoke or reject affected sessions and prevent discovery, interaction, and
  messaging access. Keep network-level bans as a separate explicit decision.
- Evidence: Enforcement tests cover existing sessions and all relevant endpoints;
  an audit record identifies who acted and why; restore/unban behavior is explicit.

### TS-05 — Define the beta appeals path through support

- Priority: P2
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Publish a support route for appeals and document who reviews them. No
  in-product appeals workflow is required for private beta.
- Evidence: Approved support playbook and user-facing contact path.

### TS-06 — Implement account closure and deletion

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Separate brand departure, platform account closure, immediate visibility
  revocation, recovery window, media purge, and legal erasure. For beta, choose
  clear minimal retention periods with legal/product approval and durable purge
  jobs rather than building a general retention engine.
- Evidence: Tests cover sessions, profiles, discovery, matches, conversations,
  reports, media, retryable provider deletion, cross-brand behavior, restoration
  within the approved window, and irreversible erasure boundaries.

