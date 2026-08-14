# Staging Capacity Investigation — 2026-08-14

## Scope and status

This investigation uses the 3,000-account synthetic HookUs dataset on
`staging-api.d8n.tech`. The deployed revision during evidence collection was
`8be05b1bffb284611d0b1c64b8cfaa84ccd403e7`.

No production system was accessed or changed. No additional high-concurrency
test was run. All request probes that could write used database transactions
that were rolled back. The discovery optimization described below has been
measured with `EXPLAIN ANALYZE` against the staging data, but has not been
deployed or load-tested. It is therefore a measured query-plan improvement, not
a claim about new end-to-end capacity.

## Existing load baseline

| Load | Correctness | Discovery p95 | Login p95 | HTTP p95 | Throughput |
| --- | --- | ---: | ---: | ---: | ---: |
| 25 VUs | no HTTP/login/discovery failures | ~1.45 s | ~986 ms | ~1.35 s | not recorded |
| 50 VUs | 1,890/1,890 checks; no failures | ~3.47 s | ~2.49 s | ~3.29 s | ~9.3 req/s |
| 100 VUs | 2,083/2,083 checks; no failures | ~9.32 s | ~9.22 s | ~9.11 s | ~10.16 req/s |

The nearly flat throughput from 50 to 100 VUs, alongside approximately tripled
latency, is saturation. During the heavy run PostgreSQL used approximately
150–180% CPU on the two-core host while memory remained available.

## Deployed process and database shape

- One Puma process, three threads (`config/puma.rb` defaults to three; neither
  `WEB_CONCURRENCY` nor `RAILS_MAX_THREADS` is set).
- Primary Active Record pool size: five.
- Solid Queue runs in its own container via `bin/jobs`, not in Puma.
- `JOB_CONCURRENCY=1` produces one worker process with three threads, plus the
  Solid Queue supervisor, dispatcher, and scheduler. Four queue-database
  connections were idle when inspected.
- PostgreSQL 17.11 has `max_connections=100`, `shared_buffers=128MB`,
  `effective_cache_size=4GB`, and `work_mem=4MB`.
- The web, worker, PostgreSQL, Date9ja, n8n, and their databases share the same
  two-core/12-GB physical host. D8N containers have no CPU or memory quotas.
- Idle inspection showed no database wait and no memory pressure. Historical
  per-request pool wait and peak connection counts were not being recorded, so
  they could not be reconstructed from the current codebase or server state.

The configured web pool is larger than the three Puma request threads, so the
web process cannot exhaust its own pool under the current topology. Increasing
the pool would not address the observed CPU saturation.

## Request paths

### Password login

```text
POST /api/v1/auth/password/login
  -> Api::V1::Auth::PasswordsController#login
  -> ApplicationController#set_current_context
  -> Brands::Resolver
  -> Identity::PasswordLogin
  -> Identity::AuthenticationLock (identifier + source-IP advisory locks)
  -> Identity::PasswordThrottle
  -> IdentityIdentifier / Credential / CredentialPasswordHash
  -> Identity::PasswordEngine -> Rodauth -> bcrypt
  -> BrandMembership
  -> Session.issue!
  -> AuthAttempt + SecurityEvent audit records
  -> Profiles::OnboardingStatus
```

### Discovery

```text
GET /api/v1/discovery
  -> Api::V1::DiscoveryController#index
  -> bearer SessionAuthenticator
  -> Matching::Discovery
  -> Matching::EligibilityScope
       lifecycle + tenant + visibility
       block exclusions
       reciprocal gender and age
       fresh location + reciprocal distance
  -> Matching::ExclusionsScope
       likes + passes + active matches
  -> Matching::Strategies::Hookus
       intent/vibe option scores + distance score
  -> Matching::Cursor
  -> bounded option preloads
  -> Matching::CandidateSerializer
```

The database remains authoritative. The query keeps existing brand, lifecycle,
block, reciprocal-preference, interaction-exclusion, score, ordering, and cursor
semantics.

## Representative request query counts at idle

These are in-container production requests against representative synthetic
records. Rails' logged count includes cached queries; the measured count excludes
schema, transaction-control, and cached statements.

| Endpoint | Status | Rails SQL (cached) | Measured uncached SQL | SQL time | Request time |
| --- | ---: | ---: | ---: | ---: | ---: |
| login | 201 | 27 (0) | 27 | ~21.5 ms | ~537 ms |
| own profile | 200 | 19 (5) | 14 | ~6.8 ms | ~91 ms |
| discovery, limit 20 | 200 | 18 (1) | 17 | ~212 ms | ~484 ms |
| matches | 200 | 10 (0) | 10 | ~22.9 ms | ~76 ms |
| like | 201 | 27 (1) | 26 | ~11.6 ms | ~84 ms |
| pass | 201 | 26 (1) | 25 | ~9.0 ms | ~65 ms |

Discovery returned 1, 10, 20, and 50 profiles with the same 16 uncached SELECTs
in a separate scaling probe. The option preloads are bounded; no discovery N+1
was found. Match cards are explicitly preloaded. Like and pass execute many
constant-count invariant/locking checks, but do not iterate a collection.

## Discovery `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` evidence

### Before

The original HookUs scorer built candidate option statistics for every public
intent/vibe selection in the brand. PostgreSQL then repeatedly scanned/sorted
that aggregate while joining each eligible candidate.

| Representative viewer | Candidates after eligibility | Planning | Execution | Shared hits | Key plan evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| Nigerian, 50 km cap | 50 | 12.5 ms | 257.2 ms | 59,588 | candidate aggregate returned 1,501 groups in 50 loops; 75,022 rows removed at join |
| Nigerian, no cap | 265 | 6.8 ms | 949.7 ms | 69,474 | candidate aggregate returned 1,501 groups in 265 loops; 397,526 rows removed at join |
| Atlanta, 100 km cap | 0 | 8.6 ms | 1.0 ms | 324 | coordinate index narrowed to 78 locations, then reciprocal filters removed them |

The slow plans had no disk reads, temporary files, or sort spill. They were
CPU/cache-buffer work. Cardinality estimates were poor (for example eight
profiles estimated versus 626 actual), despite current autovacuum statistics.
The important issue was query shape, not stale statistics.

Existing indexes were used for viewer/candidate locations, likes, passes,
blocks, option selections, users, memberships, and preferences. Sequential scans
of 3,000 profiles took about 2 ms; the two 205-row match scans took roughly
0.03 ms each. No new index is justified by these plans.

### Query-shape change

`Matching::Strategies::Hookus` now computes the same four intent/vibe aggregates
with a correlated `LEFT JOIN LATERAL` for each already-eligible candidate. It no
longer builds and repeatedly rejects a brand-wide candidate-statistics result.
All score formulas and eligibility/order/cursor behavior remain unchanged.

### After, on the same staging data

| Representative viewer | Execution | Shared hits | Plan improvement |
| --- | ---: | ---: | ---: |
| Nigerian, 50 km cap | 12.8 ms | 10,321 | 257.2 -> 12.8 ms (~95% lower plan time) |
| Nigerian, no cap | 41.5 ms | 42,053 | 949.7 -> 41.5 ms (~96% lower plan time) |

This is direct `EXPLAIN ANALYZE` evidence for the revised SQL against live
staging data. It is not an end-to-end k6 result. A controlled rerun belongs on
the eventual isolated Hetzner proving host after this change is reviewed,
committed, deployed, and observed.

## Login findings

- Stored hashes use bcrypt cost 12. Five direct checks averaged ~251 ms; five
  checks through `PasswordEngine` averaged ~257 ms. This is expected security
  work and must not be weakened to improve a benchmark.
- An idle successful login took ~537 ms. Its 27 SQL statements consumed only
  ~21.5 ms; the session insert was the slowest single statement at ~5 ms.
  Password verification and application work, not identifier lookup, dominate.
- The transaction holds both identifier and source-IP advisory locks across
  throttle checks, bcrypt, session issuance, and audits. A three-thread probe
  with a 100 ms critical section took ~308 ms using one IP versus ~186 ms with
  distinct IPs, confirming same-IP serialization.
- Staging logs show all k6 logins came from `160.119.35.237`. The login portion
  of this single-generator test therefore measures the deliberate IP lock as
  well as bcrypt/server capacity. Carrier-NAT users can create a smaller version
  of the same contention in real traffic.

The lock must not simply be removed: it currently makes throttle decisions
race-safe. A future change needs an explicit reservation/counting design and
security/concurrency tests. Until then, retain bcrypt cost and locks; measure
non-authenticated endpoint capacity with pre-issued sessions or distributed load
sources, and keep a separate authentication stress scenario.

## Root cause and remaining risks

The first demonstrated bottleneck is shared CPU, led by the original discovery
option aggregate and compounded by bcrypt. PostgreSQL, Puma, the worker, and
unrelated services contend for two physical cores. Once the three Puma threads
are occupied, additional requests queue; doubling VUs therefore raises latency
without useful throughput.

Connection-pool exhaustion was not demonstrated. There were no temp spills,
deadlocks, meaningful physical reads, or memory pressure. Exact connection wait
during the completed load run could not be verified because pool-wait metrics
and historical `pg_stat_activity` samples were not captured.

Remaining performance risks to measure later:

- no-distance discovery evaluates more candidates and remains the worst query;
- option/location work still grows with eligible candidates and should be
  revisited at materially larger datasets;
- likes/passes/matches will grow beyond the current ~5k/~9k/~205 rows;
- messaging is absent from this dataset and will change the workload shape;
- a shared-IP auth test is not a proxy for geographically distributed login;
- the current Oracle host is noisy and is explicitly not the final capacity
  certification environment.

## Hetzner proving assumptions

Do not select a production SKU from this run alone. For the deliberately simple
single-host beta shape (Rails/Puma + PostgreSQL + separate Solid Queue process),
the next proving environment should have at least four dedicated CPU cores,
16 GB RAM, fast NVMe storage, and off-host backups. If only shared-vCPU products
are considered, use more CPU headroom rather than treating a shared vCPU as a
dedicated core.

A sensible first test configuration is two Puma workers with three threads each,
a connection pool equal to the per-worker thread count, and the existing bounded
Solid Queue worker. Keep the total PostgreSQL budget below roughly 25 connections
including workers, migrations, consoles, and operational reserve. These are test
assumptions, not a purchase recommendation or capacity promise.

Certification must repeat the representative workload on an isolated candidate
host, separately measure authenticated and pre-authenticated flows, capture
Puma queueing, Active Record checkout waits, PostgreSQL query/CPU statistics,
Solid Queue depth, and p50/p95/p99 latency, then stop at the first saturation
point. The existing document's 250–1,000-concurrent expectations are hypotheses,
not evidence.
