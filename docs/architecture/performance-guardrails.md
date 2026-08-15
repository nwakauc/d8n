# D8N Performance & Architecture Guardrails

## Purpose

This document exists to keep D8N fast, secure, cheap, and operationally simple **without redesigning the platform prematurely**.

D8N remains a Rails modular monolith with PostgreSQL, Solid Queue, Kamal, and private object storage. This document does not replace that architecture. It defines how we evaluate performance concerns, what we optimize now, what we defer, and what evidence must exist before introducing additional complexity.

The governing rule is:

**Do not optimize because something could become a problem. Optimize when the current architecture shows evidence of becoming the problem.**

The exception is inexpensive launch-safety work that prevents known failure modes.

---

## Core Architecture We Keep

D8N should remain structurally simple:

**Client applications**
→ Rails API
→ PostgreSQL

with:

**Client applications**
→ short-lived signed URL from Rails
→ R2 directly for media upload/download

and:

**Rails**
→ Solid Queue
→ asynchronous jobs such as email, SMS, media processing, moderation, cleanup, and notifications.

Application nodes remain stateless.

No Kubernetes, microservices, distributed databases, event-bus architecture, or separate service fleet should be introduced without measured evidence that the existing architecture cannot meet requirements.

---

## Decision Categories

Every architecture/performance issue should be classified into one of four buckets.

### KEEP

The current implementation is correct for our scale. Do not touch it unless metrics or product requirements change.

### FIX BEFORE LAUNCH

The issue presents a clear reliability, security, cost, or user-experience risk even at modest scale.

Fix it before meaningful production traffic.

### FIX WHEN METRICS SAY SO

The design is acceptable now but has a known scaling limit.

Document the threshold, monitor it, and change it only when the threshold is approached.

### DO NOT OPTIMIZE YET

The proposed improvement increases operational or architectural complexity without solving a demonstrated problem.

Leave it alone.

---

# 1. Media Delivery

## Direction

Media bytes should not normally pass through Rails.

Rails remains responsible for authorization and ownership, while R2 carries the actual image/video traffic.

Preferred flow:

1. Client requests permission to upload.
2. Rails authenticates the user and validates intended media metadata.
3. Rails creates an upload intent/object record.
4. Rails issues a short-lived signed R2 upload URL.
5. Client uploads directly to R2.
6. Upload is finalized/verified.
7. Rails records the media as available.

Private downloads follow the same principle:

1. Client requests access.
2. Rails verifies authorization.
3. Rails returns a short-lived signed access URL.
4. Client downloads directly from R2.

## Classification

**FIX BEFORE LAUNCH**

Direct client-to-R2 should be the production media path for profile photos, user images, and supported videos.

## Important follow-up

Direct uploads solve transport cost and server load, but not media optimization.

We must avoid serving original high-resolution files where smaller variants are sufficient.

Profile cards, thumbnails, chat previews, and other fixed display contexts should use appropriately sized variants.

Video processing can evolve later according to actual usage.

---

# 2. Database Performance

PostgreSQL is expected to become the primary scaling constraint before Rails itself.

We should optimize the database using evidence rather than assumptions.

## Watch

* slow query duration
* p95/p99 database latency
* index usage
* sequential scans on large tables
* connection count
* lock contention
* discovery query execution time
* messaging query execution time
* queue database contention
* database CPU and disk I/O

## Classification

**KEEP** PostgreSQL as the primary datastore.

**FIX BEFORE LAUNCH** obvious missing indexes, pathological queries, and connection-pool misconfiguration.

**FIX WHEN METRICS SAY SO** replicas, database separation, aggressive caching, or more advanced topology.

---

# 3. Discovery Queries

Discovery is expected to become one of the most important database workloads.

It may include:

* profile visibility
* gender/orientation compatibility
* age range
* geographic distance
* preferences
* blocked users
* previous passes
* previous likes
* matches
* account state
* verification/trust state
* product-specific filters

## Rules

Do not redesign discovery prematurely.

Instead:

* inspect query plans
* test with realistic seeded datasets
* measure p95 latency
* ensure appropriate indexes exist
* eliminate unnecessary joins
* verify that pagination remains efficient

## Classification

**FIX BEFORE LAUNCH** if discovery is already slow on production-scale synthetic data.

Otherwise:

**KEEP and monitor.**

---

# 4. N+1 Queries

Rails makes N+1 query problems easy to introduce.

Important endpoints should be checked for repeated per-record queries.

Likely candidates:

* discovery
* profile views
* matches
* conversations
* message lists
* notifications
* admin lists

The goal is not zero SQL queries.

The goal is avoiding query count that grows linearly because associations were loaded carelessly.

## Classification

**FIX BEFORE LAUNCH** for high-traffic endpoints with clear N+1 behavior.

---

# 5. API Payload Size

The API should send what the client screen needs, not entire database representations.

For example, a discovery card may need:

* id
* display name
* age
* primary image
* distance
* short bio
* verification state
* limited product-specific metadata

It does not need every profile field.

## Why this matters

Smaller payloads improve perceived speed and reduce data usage, especially on mobile networks.

## Classification

**KEEP SIMPLE NOW**, but remove obviously oversized responses before launch.

---

# 6. Pagination

Large feeds should avoid designs that become increasingly expensive as users move deeper into a dataset.

Cursor/keyset pagination should be preferred for workloads where traditional large-offset pagination becomes expensive.

Priority areas:

* discovery feeds
* conversations
* message history
* notifications
* admin tables with large datasets

## Classification

**FIX WHEN METRICS SAY SO**, unless current implementation already exhibits poor performance.

---

# 7. Caching

Caching should solve measured repeat work.

It should not become a second data architecture.

Good candidates may include:

* public/static configuration
* feature configuration
* expensive derived data
* media/CDN responses
* rarely changing lookup data

Poor candidates include state that must remain immediately correct for:

* blocks
* safety actions
* permissions
* account restrictions
* message authorization
* match state

## Rule

Do not introduce Redis merely because caching is possible.

Use caching when repeated computation or database work is demonstrated to matter.

## Classification

**DO NOT OPTIMIZE YET**, except for obvious CDN/media caching.

---

# 8. Background Jobs

Work the user does not need completed inside the HTTP request should normally be asynchronous.

Examples:

* email
* SMS
* push notifications
* media analysis
* image variants
* video processing
* moderation processing
* media deletion
* cleanup
* analytics aggregation

The API should complete quickly and delegate slow work where appropriate.

## Classification

**KEEP Solid Queue.**

Move expensive synchronous work to jobs when discovered.

Do not introduce separate queue infrastructure unless Solid Queue becomes a measured bottleneck.

---

# 9. Messaging

Messaging should prioritize correctness before real-time sophistication.

The durable source of truth should be PostgreSQL.

Expected pattern:

1. authenticate sender
2. authorize conversation
3. persist message
4. commit successfully
5. broadcast message/update

Real-time delivery is an enhancement to persisted state, not a replacement for it.

We should test:

* reconnect behavior
* message ordering
* duplicates
* unread counts
* failed broadcasts
* blocked users
* deleted accounts
* conversation authorization

## Classification

**FIX BEFORE LAUNCH** for persistence, authorization, and blocking correctness.

Advanced real-time optimization is:

**FIX WHEN METRICS SAY SO.**

---

# 10. Rate Limiting & Abuse

Dating applications are high-abuse environments.

The system should have sensible protections around:

* login attempts
* registration
* verification requests
* password reset
* likes
* matches where applicable
* DMs/messages
* reports
* signed upload URL creation
* media upload size
* API scraping
* repeated failed requests

Rate limits must be proportional to actual product behavior and should not interfere with normal users.

## Classification

**FIX BEFORE LAUNCH** for authentication, messaging, verification, and upload surfaces.

---

# 11. Database Connections

Connection exhaustion may appear before CPU exhaustion.

The following should be treated as one shared connection budget:

* Puma workers/threads
* Solid Queue workers
* maintenance jobs
* consoles
* admin processes
* future application nodes

Monitor:

* active connections
* idle connections
* pool wait time
* failed checkouts

PgBouncer should be introduced when connection pressure justifies it rather than simply because it exists.

## Classification

Correct pool sizing:

**FIX BEFORE LAUNCH**

PgBouncer:

**FIX WHEN METRICS SAY SO**

---

# 12. Observability

We cannot optimize what we cannot measure.

Minimum useful signals:

* request rate
* error rate
* p50 latency
* p95 latency
* p99 latency
* CPU
* RAM
* disk usage
* disk I/O
* PostgreSQL connections
* slow queries
* queue depth
* failed jobs
* media upload failures
* R2 errors
* email/SMS delivery failures

## Rule

Every future scaling decision should reference measurements where practical.

## Classification

Basic production observability is:

**FIX BEFORE LAUNCH**

Large observability platforms and elaborate dashboards are:

**DO NOT OPTIMIZE YET**

until needed.

---

# 13. Failure Paths

Normal operation is not enough.

We should know what happens when:

* R2 is temporarily unavailable
* upload succeeds but finalize fails
* client disconnects during upload
* worker crashes
* job retries
* PostgreSQL restarts
* email provider fails
* SMS provider fails
* Action Cable disconnects
* one app node disappears
* deployment partially fails

Failure handling should favor retryability and idempotence.

## Classification

Critical user/data integrity paths:

**FIX BEFORE LAUNCH**

Rare infrastructure resilience improvements:

**FIX WHEN METRICS SAY SO**

---

# 14. Multi-Brand Identity

D8N may serve multiple consumer brands.

Shared infrastructure must not automatically imply shared UX.

The platform may internally recognize a common identity while Date9ja, HookUs, and future brands remain distinct products.

Authentication boundaries, password behavior, consent, account discovery, and cross-brand identity should be deliberate.

Do not accidentally create a confusing cross-brand login experience simply because the databases are shared.

## Classification

Architecture decision:

**DOCUMENT BEFORE EXPANSION**

Implementation should remain as simple as possible until multiple production brands require it.

---

# 15. Performance Testing

Synthetic tests should answer real questions.

Before increasing infrastructure complexity:

1. reproduce the issue
2. measure the bottleneck
3. identify the constrained resource
4. make the smallest change likely to fix it
5. rerun the same workload
6. compare before/after results

Useful signals:

* requests/second
* concurrent users
* p50/p95/p99 latency
* HTTP error rate
* CPU
* RAM
* DB CPU
* DB I/O
* connection saturation
* queue depth

Performance tests should resemble actual product workflows rather than artificial endpoint hammering.

---

# 16. Scaling Order

When D8N experiences growth, prefer scaling in approximately this order:

1. Fix pathological queries.
2. Fix N+1 queries.
3. Add missing indexes.
4. Reduce oversized payloads.
5. Tune connection pools.
6. Move expensive work out of web requests.
7. Increase server resources.
8. Add additional stateless Rails nodes.
9. Introduce connection pooling infrastructure if required.
10. Scale PostgreSQL vertically.
11. Add replicas if read pressure justifies them.
12. Introduce additional services only where a clear bottleneck demands them.

Do not jump directly from “server is busy” to microservices.

---

# 17. Architecture Change Rule

A major architectural change should answer four questions:

**What measurable problem exists?**

**Why can the current architecture not solve it reasonably?**

**What is the smallest viable change?**

**What new operational burden does the change introduce?**

If those questions cannot be answered, the change should probably not be made.

---

# Current D8N Position

The existing direction remains appropriate:

* Rails modular monolith
* PostgreSQL
* Solid Queue
* Kamal
* stateless application nodes
* private R2 media
* direct signed client uploads/downloads
* asynchronous background processing
* boring VPS infrastructure
* performance testing before scaling decisions

The purpose of optimization is not to make D8N architecturally impressive.

The purpose is to make the products feel fast and reliable while keeping the company inexpensive and easy to operate.

---

# Working Audit Checklist

When reviewing a D8N feature or endpoint, ask:

* [ ] Is this request doing unnecessary synchronous work?
* [ ] Are large media bytes passing through Rails unnecessarily?
* [ ] Is the API returning more data than the screen needs?
* [ ] Are there N+1 database queries?
* [ ] Does the query have the indexes it needs?
* [ ] Is pagination appropriate for expected dataset size?
* [ ] Could this work safely happen in Solid Queue?
* [ ] Could one user abuse this endpoint and create disproportionate cost?
* [ ] What happens when the external dependency fails?
* [ ] Can we observe the failure?
* [ ] Do we have evidence that further optimization is necessary?

If the answer to the final question is no, prefer the simpler implementation.
