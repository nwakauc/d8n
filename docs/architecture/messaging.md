# D8N Messaging Architecture

## Implementation Sequence

### Slice 1: Conversation Boundary

- One durable, brand-owned conversation per match.
- Two explicit profile participants created atomically under a match lock.
- Idempotent conversation start and participant-scoped cursor listing.
- Database tenant constraints and public UUIDs.
- No message-content column or endpoint.

Gate: concurrency, cross-brand, non-participant, lifecycle, soft-deletion, cursor, serializer, and query-count tests pass.

### Slice 2: Text Messages And Read State

- Bounded text-only messages with public UUIDs.
- Participant-authorized history and send commands.
- Opaque chronological cursor polling.
- Per-participant read position.
- Message-content log filtering and send throttling.
- Explicit Trust block and report-evidence interfaces.

Gate: blocked participants cannot send, reports can retain authorized evidence, and content never appears in logs or unrelated serializers.

### Slice 3: Delivery Integration

- After-commit notification handoff without message bodies by default.
- Poll reconciliation semantics and optional authorized realtime events.
- Delivery/read event idempotency.

### Slice 4: Media And Rich Interaction

- Media-owned attachments after secure delivery and moderation exist.
- Replies, edits, reactions, and deletion behavior only with explicit migration and moderation semantics.

## Initial API Shape

```txt
POST /api/v1/matches/:match_id/conversation
GET  /api/v1/conversations
```

Future message routes are deliberately absent until Slice 2.

## Privacy Rules

- Conversation and message APIs use public UUIDs.
- Participant payloads use public profile serialization.
- Message content is never part of generic logs, analytics, security events, or exception metadata.
- Brand administrators receive no implicit message access.
- Cross-brand access is denied even when the same platform user belongs to both brands.
- Soft deletion and user-facing deletion do not define legal erasure; retention and erasure require separate workflows.
