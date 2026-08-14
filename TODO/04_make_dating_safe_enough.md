# Milestone 4 — Make Dating Safe Enough

Outcome: beta users can stop contact, report harm, receive a human review, and
have enforcement applied consistently. A formal appeals product and a security
operations organization are not beta requirements.

## Tasks

### TS-01 — Preserve and verify blocking across every user path

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Keep existing brand-scoped directional blocks and prove they prevent
  discovery, likes/passes, match access, conversation access, and future message
  sends in either direction where required.
- Evidence: Cross-endpoint request tests cover both block directions, existing
  matches/conversations, suspended/deleted participants, and tenant isolation.

### TS-02 — Add bounded user reporting

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Implement brand-scoped profile/photo/message reporting with bounded reason
  codes and optional bounded user context. Preserve only the evidence required for
  review; never copy private message content into generic logs or audit metadata.
- Evidence: Authorization, tenant-isolation, duplicate/abuse-limit, evidence-access,
  deletion interaction, and serialization tests pass.

### TS-03 — Provide a minimal admin review queue

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Allow explicitly authorized D8N beta moderators to list and review reports
  for permitted brands and record a decision. Use a small permission model for the
  actual beta team; do not build enterprise RBAC or external-operator support now.
- Evidence: Admin authentication, brand authorization, sensitive-read auditing,
  decision auditing, and denial tests exist. Admin MFA is enabled before real user
  data is accessible.

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

