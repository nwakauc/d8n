# ADR 0010: Use Match-Gated Private Messaging

## Status

Accepted for Phase 5 Slice 1 on 2026-08-13. Message-content APIs remain blocked on the Slice 2 safety gate.

## Context

D8N messaging contains highly sensitive private content and must support different dating brands without cross-brand disclosure. HookUs and the live Date9ja application both gate chat through a match, but their legacy implementations attach messages directly to platform users and combine text, media, reactions, read state, realtime delivery, notifications, deletion, and reports in one controller surface.

D8N separates network `User` identity from brand `Profile` participation. Messaging must preserve that boundary, provide migration targets for Date9ja, and leave explicit integration points for Trust, Media, Notifications, and realtime delivery.

## Decision

### Conversations Belong To A Brand Match

One durable conversation may exist for one match. A conversation references its brand and match and receives an unguessable public UUID. It is created lazily and idempotently when a participant opens the chat; match creation does not gain messaging side effects.

The initial product is one-to-one, but participants are explicit records so per-participant read, archive, deletion, and future delivery state do not become columns duplicated on `Conversation` or `Match`.

Conversation participants are brand profiles, not platform identities. Participant records also carry the owning user and brand so database constraints can prove tenant consistency with the profile. Every conversation and participant query starts from the authenticated user's current-brand profile.

### Access Is Rechecked

A public match or conversation identifier is not authorization. Creating, listing, reading, or writing rechecks current brand, participant membership, current user/membership/profile lifecycle, match status, and soft-deletion state.

Cross-brand, non-participant, deleted, and unavailable conversations return the same not-found response where practical. This prevents resource enumeration.

An ended match makes a conversation read-only; it does not erase history. A participant whose own account, membership, or profile is unavailable cannot access messaging. Counterpart suspension and legal retention behavior must be finalized before message-content APIs ship.

### Message Content Is A Separate Safety Slice

Phase 5 Slice 1 stores no message content. Slice 2 must add text messages only after all of these are implemented together:

- bounded body length and Unicode normalization;
- request-log filtering that prevents content from entering logs;
- participant and active-match authorization at read and write time;
- brand-scoped message cursors and stable public message IDs;
- per-participant read state;
- send throttling and abuse limits;
- explicit block-policy integration that denies new sends;
- message-reporting evidence handoff that does not copy content into generic logs;
- retention, export, soft-deletion, and legal-erasure behavior;
- tests proving no cross-brand or non-participant access.

Attachments remain deferred to the Media domain. Reactions, edits, replies, typing state, realtime sockets, push/email notifications, and message search are also deferred.

### Do Not Log Private Content

Message bodies, attachment payloads, report evidence, and notification previews are private message data. They must not appear in request logs, audit metadata, analytics payloads, exception context, or ordinary notification payloads.

Operational events may record opaque message/conversation public IDs, brand ID, actor profile ID, event type, timestamps, and delivery outcome without content.

### Polling Before Realtime

The first delivery path is bounded cursor polling. Realtime delivery may be added later using the same authorization and serialization policy. Clients must treat realtime events as hints and reconcile through the canonical HTTP cursor API.

## Slice 1 Contract

Slice 1 may implement:

- tenant-constrained `Conversation` and `ConversationParticipant` records;
- idempotent `POST /api/v1/matches/:match_id/conversation`;
- participant-scoped, cursor-paginated `GET /api/v1/conversations`;
- public counterpart profile serialization without messages or private identifiers.

Slice 1 did not claim the Phase 5 acceptance criteria for blocked users or message reporting were complete. A subsequent Trust slice now denies conversation creation and listing in either block direction while preserving retained conversation metadata. Message reporting and its evidence-access policy remain incomplete.

## Date9ja Migration Gate

Before importing Date9ja conversations or messages, inventory source counts, match/message ownership, deleted and edited records, read timestamps, attachment types, orphan records, support conversations, reactions, replies, and identifier ranges. Migration must preserve source IDs in a dedicated mapping/audit mechanism rather than exposing them as D8N public IDs.

## Consequences

- Messaging remains brand-profile scoped while identity remains network scoped.
- Conversation creation is safe to retry and does not enlarge the match transaction.
- Explicit participant state supports read/archive behavior without assuming all future conversations are identical.
- Message delivery takes more slices. Blocking now exists, but private content cannot ship before reporting and the remaining privacy controls exist.
- Date9ja remains a migration source rather than an architecture template.

## Alternatives Considered

- Store messages directly on `Match` with a `sender_user_id`.
- Create a conversation synchronously inside reciprocal-like match creation.
- Ship text, media, reactions, realtime, and reports in one phase.
- Permit messaging after a match without rechecking lifecycle or block policy.
- Store private message content in notifications, analytics, or generic audit metadata.
