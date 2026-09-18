# Member realtime and message read state

Status: local implementation for owner-requested Date9ja realtime UX (2026-09-18).
D8N owns this reusable mechanism. No production changes or independent approval.

Reuse Rails Action Cable's configured pubsub adapter (PostgreSQL in production)
with SSE browser transport at `/api/v1/member_events`, which works through the
same-origin HTTP BFF without changing session cookie scope or exposing tokens.
No websocket deployment, Redis, separate broker, provider or outbox redesign.
Message events carry opaque IDs only; inbox events reuse the existing safe
notification presenter (generic copy and opaque payload IDs, never content). After-commit events are ephemeral hints; HTTP
snapshots always own counts. Each process has one PostgreSQL pubsub listener;
each stream consumes a Live thread, not a permanently checked-out AR connection.
A 100-item queue bounds backpressure. Streams end after 240 seconds, reconnect,
and emit reconciliation heartbeats every 15 seconds. Verify proxy flushing,
function-duration limits, concurrent stream/thread capacity and disconnect
cleanup in the target hosting environment before owner-controlled deployment.

`message_reads` records one receipt per recipient profile/message, with tenant
foreign keys and unique pair. Explicit acknowledgments accept up to 100 actual
message public IDs; unseen concurrent messages are never marked read. Global
unread messages are all kept incoming messages in the canonical available,
unblocked current-brand participant conversation scope minus persisted receipts.
This is neither unread-conversation count nor unread notification count. Own,
deleted and inaccessible messages are excluded. Existing histories have no
read evidence: they remain unread until displayed and acknowledged. No guessed
legacy read position, historical backfill or migration code is introduced.

Reading notifications does not mark messages read. Reading displayed messages
marks matching inbox notifications read, including delayed materialization.
Unread global/per-card state is reconciled on initialization, connection-ready,
heartbeat/focus, and after successful read operations. No event replay or count
increment is trusted. Session/user/credential/brand/membership validity is
rechecked before delivery and at heartbeat. Server-side participant authorization
remains authoritative for message/history reads; event hints reveal no content.
