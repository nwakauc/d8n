# ADR 0018: Content-level reporting and evidence (Reporting V2)

## Status

Accepted on 2026-08-19. Extends the profile-only reporting foundation (TS-02,
ADR-less) into a reusable content-reporting seam for HookUs and future D8N brands.
Builds on blocking (ADR 0009/0010), the admin review queue (TS-03), account
enforcement (ADR 0013), and account closure (ADR 0014). It deliberately does NOT
build image/video messaging, Private Albums, or automated enforcement.

## Context

Reporting needed to grow from "report this person" to "report this message /
photo / Hook", and to be the foundation the next milestones (image/video
messaging, Private Albums) can reuse without a redesign. The existing `reports`
table, `Trust::ReportProfile`, rate limiting, and admin queue were sound and had
to be preserved, not replaced.

Two forces shaped the design: **brand isolation + IDOR safety** (a reporter must
never learn about, or report, content they can't legitimately access, across any
brand), and **evidence durability** (a report must remain meaningful after the
reported message/photo/Hook is later deleted, without turning a report into a copy
of an entire conversation or a permanent copy of private media).

## Decision

### Responsible profile + polymorphic target, not a nullable column per type

`reports.reported_profile_id` stays NOT NULL and keeps meaning **the responsible
person** — but for content reports it is *derived server-side* from the target
(message sender, photo owner, Hook sender), never trusted from the client. The
specific content is identified by a two-column polymorphic seam: `target_type`
(int enum: `profile`/`message`/`profile_media`/`hook`, appended as features ship)
plus `target_id` (the internal record id; NULL only for a plain profile report).
No `message_id`/`photo_id`/`hook_id`/… column sprawl. A new target type is one
resolver, not a schema change.

### Per-target authorization lives in resolvers, not controllers

`Trust::ReportTargets::{Profile,Message,Media,Hook}Target` each answer one
question — "may THIS viewer report this target, and who is responsible?" — and
return a `Resolution(target_type, target_id, reported_profile, evidence)`. Every
failure raises the same neutral `AccessError(:target_unavailable)`, so unknown,
inaccessible, self-owned, deleted, and cross-brand targets are indistinguishable.
`Trust::FileReport` owns the target-agnostic invariants (authenticated reporter,
reason validity, duplicate suppression, audit, optional block). The legacy
`POST /profiles/:id/report` is a thin shim over the same path and keeps its exact
old contract (including the `profile_unavailable` code).

Authorization is intentionally target-specific:

- **message** — the viewer must be a `ConversationParticipant` of the message's
  conversation. This is deliberately NOT `MatchAccess`: reporting must survive a
  block/suspension/closure of the sender, so a previously received message stays
  reportable from retained history (a blocked/suspended/closed sender does not
  erase the report path). A viewer cannot report their own message.
- **profile_media** — the owner must be visible to the viewer under the same
  `Matching::VisibilityScope` discovery/profile-view uses (brand isolation,
  active/visible, min-age, blocks either way) and the photo must be deliverable.
  Unlike a message, a photo is only reportable while you can legitimately see it.
- **hook** — only the recipient may report, and only a Hook addressed to them; any
  status (pending/accepted/declined/expired) is reportable.

### Evidence is a minimal immutable snapshot on the report row

A `reports.evidence` jsonb holds only what moderation needs to understand what was
flagged if the target later disappears: for a message, the sender/conversation
ids, type, body, and timestamp; for a Hook, the opener text + status; for a photo,
the opaque photo id, position, and lifecycle state. It never contains surrounding
conversation history, whole profiles, R2 object keys, storage paths, URLs, or auth
data. It is moderator-only and is never exposed to the reporter. Reported content
text is NEVER placed in application logs or `SecurityEvent` metadata — the audit
event (`trust.report_created`) identifies records only.

### Duplicate suppression is a DB invariant, separate from rate limiting

Two partial-unique indexes enforce "at most one OPEN report per (reporter,
target)": one for profile reports (`target_id IS NULL`) preserving the original
idempotency, one for content reports on `(brand, target_type, target_id)`. So
Message A, Message B, and Photo C from the same person can each be reported, while
a repeat of the same target is idempotent (`created: false`) even under concurrent
double-submit (unique index + `RecordNotUnique` retry). This content-level
invariant is independent of the generic abuse ceiling (`report_profile` rate
limit), which remains the outer 429 guard.

### Report and block, but never auto-enforce

The generic endpoint accepts an optional `block: true` that blocks the responsible
profile after the report is filed (both idempotent). Reports never automatically
suspend, ban, hide, or otherwise enforce — a report is evidence for human/system
review (ADR 0013 enforcement stays a separate, explicit moderator action).

## Media evidence retention: a documented beta limitation

A reported photo's ProfilePhoto row is soft-deleted (not hard-deleted) on account
closure, so the report's identification evidence always survives. However, the
underlying R2 objects are still purged by `Media::PurgeProfileMediaJob` on closure:
the pixels can disappear while a report is open. Building a media legal-hold /
retention system is out of scope for beta (proportionality — this is not a bank).
The seam for it is the stable `target_id` + photo `public_id`; a future
`ModerationHold` can suspend purge for objects under open reports. Until then this
limitation is accepted and documented.

## Consequences

- `profile_photos` gains a stable `public_id` (additive, backfilled) so members can
  reference a specific photo without exposing its internal id or R2 key.
- The audit event for profile reports changes from `trust.profile_reported` to the
  unified `trust.report_created`; downstream analytics keying on the old name must
  update. No user-facing API changed.
- Moderators see `target_type` + `evidence` in the existing queue/detail; no new
  admin subsystem was built.

## Future extension

`chat_media`, `private_album_media`, `video`, `marketplace_listing`, and `event`
become new `target_type` enum values + one resolver each, reusing FileReport,
evidence, duplicate suppression, rate limiting, and the admin queue unchanged. The
features themselves are out of scope here.
