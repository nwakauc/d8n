# D8N Starting Infrastructure Architecture & Server Shopping Spec

**Status:** Approved Starting Point
**Purpose:** Define exactly what infrastructure D8N should look for, whether free or paid, before production growth.
**Initial Capacity Goal:** Comfortable early production, prove 1,000 active concurrent users, architect toward 5,000+ concurrent users without redesigning the platform.

---

# 1. Starting Architecture

D8N should begin with **three servers** where practical.

```text
                         INTERNET
                            │
                            ▼
                       Cloudflare
                            │
                            ▼
                     Load Balancer
                     /           \
                    /             \
                   ▼               ▼
          APP SERVER #1      APP SERVER #2
             JHB                 JHB
          Rails / Puma        Rails / Puma
          Realtime            General workers
          Critical jobs       useSend initially
                   \             /
                    \           /
                     \         /
                         ▼
                    DB SERVER
                       JHB
                    PostgreSQL
                    PgBouncer
                    Backups
```

External services:

```text
Cloudflare R2
→ photos
→ videos
→ uploaded media

Amazon SES
→ outbound email

Termii / Twilio
→ SMS

FCM / APNs
→ mobile push notifications
```

Future internal-tools server:

```text
TOOLS SERVER
────────────
n8n
OpenClaw
useSend
internal automation
content workflows
admin/internal tools where appropriate
```

This fourth server is **not required immediately**.

---

# 2. Server #1 — PostgreSQL Database

## Role

Dedicated D8N database server.

This should be the most protected server in the architecture.

## Minimum Acceptable Shape

```text
2 vCPU
12 GB RAM
SSD storage
```

This matches the type of Oracle ARM machine we are currently considering.

## Preferred Paid Shape

When shopping without free-tier constraints:

```text
4 vCPU
16 GB RAM
SSD / NVMe
```

## Strong Growth Shape

Later:

```text
8 vCPU
32 GB RAM
NVMe
```

Do not buy this initially unless pricing is unusually attractive.

## What Runs Here

```text
PostgreSQL
PgBouncer
database monitoring
backup agent
```

Potential logical databases:

```text
d8n_production

d8n_cache
d8n_queue
d8n_cable

usesend_production
```

They may live on the same PostgreSQL machine while remaining logically separated.

## What Must NOT Run Here

Avoid:

```text
Rails web
n8n
OpenClaw
content automation
image processing
browser automation
marketing scraping
general-purpose apps
```

Keep the DB server boring.

---

# 3. Database Storage Requirements

When shopping, prioritize:

1. SSD minimum
2. NVMe preferred
3. good IOPS
4. reliable persistent storage
5. enough disk growth capacity

Starting storage target:

```text
100 GB minimum
```

Preferred if affordable:

```text
200+ GB
```

Media should **not** live here.

Photos/videos belong in R2.

---

# 4. Database Networking

The database should ideally live in:

```text
Johannesburg
```

with the Rails nodes also in Johannesburg.

The ideal path is:

```text
Rails
  │
  │ private networking
  ▼
PostgreSQL
```

NOT:

```text
Rails
  │
  ▼
public internet
  │
  ▼
PostgreSQL
```

PostgreSQL port `5432` should never be open to the entire internet.

Only approved application servers should be allowed to connect.

---

# 5. Server #2 — Primary Rails App Server

## Minimum Acceptable Shape

```text
2 vCPU
8–12 GB RAM
SSD
```

Our Oracle target:

```text
2 vCPU
12 GB RAM
```

is fine as a starting node.

## Preferred Paid Shape

If buying:

```text
4 vCPU
8–16 GB RAM
SSD / NVMe
```

This is the shape to actively shop for if pricing allows.

## What Runs Here

```text
D8N Rails API
Puma
critical Solid Queue workers
realtime / Solid Cable
Kamal/Docker
monitoring agent
```

This server should remain as clean as possible.

No experimental automation.

---

# 6. Server #3 — Secondary Rails App Server

This gives D8N application redundancy and additional capacity.

## Minimum Acceptable Shape

```text
2 vCPU
8–12 GB RAM
SSD
```

Again:

```text
2 vCPU
12 GB RAM
```

is a valid early target.

## Preferred Paid Shape

```text
4 vCPU
8–16 GB RAM
```

## What Runs Here Initially

```text
D8N Rails
Puma
general background workers

useSend
Redis for useSend
```

Potentially later, while traffic remains low:

```text
n8n
OpenClaw
admin/internal tooling
```

but these are **secondary workloads**.

---

# 7. Server #3 Rule

Server #3 is:

**Rails server first. Internal-tools server second.**

If application traffic rises:

```text
STOP / MOVE:
n8n
OpenClaw
useSend
heavy analytics jobs
automation

KEEP:
Rails
Puma
critical workers
```

User experience always wins.

---

# 8. Future Server #4 — Automation & Internal Tools

This is intentionally postponed.

When D8N growth automation becomes serious:

```text
SERVER #4

n8n
OpenClaw
useSend
Redis
content automation
SEO workflows
campaign automation
internal support tooling
```

This server does NOT need Johannesburg-level DB latency.

A cheap Hetzner machine may be suitable here.

## Suggested Shape

Minimum:

```text
2 vCPU
4 GB RAM
```

Preferred:

```text
4 vCPU
8 GB RAM
```

If doing significant browser automation:

```text
4 vCPU
8–16 GB RAM
```

---

# 9. Location Priority

## Database

**Johannesburg required/preferred.**

## Rails #1

**Johannesburg preferred strongly.**

## Rails #2

**Johannesburg preferred strongly.**

Avoid routinely serving traffic from Europe to a Johannesburg PostgreSQL database because Rails makes many DB round trips.

## Automation Server

Location less important.

Europe is acceptable.

---

# 10. Oracle Target

Oracle currently operates the Johannesburg region:

```text
South Africa Central
af-johannesburg-1
JNB
```

When provisioning Oracle, look for:

```text
VM.Standard.A1.Flex
Ampere ARM
```

Target:

```text
2 OCPU
12 GB RAM
```

if your account/capacity permits.

Important:

Oracle's Always Free Ampere allocation is currently approximately:

```text
2 OCPU
12 GB RAM TOTAL
```

per tenancy, usable across one or two VMs.

Do not plan on receiving unlimited separate free servers from one tenancy.

---

# 11. Paid Server Shopping Spec

When looking at any provider, ignore marketing names first.

Look at these actual numbers.

## Rails Node — Good

```text
4 vCPU
8 GB RAM
80+ GB SSD/NVMe
good bandwidth
Ubuntu 24.04
Johannesburg/South Africa
```

## Rails Node — Better

```text
4 vCPU
16 GB RAM
100+ GB SSD/NVMe
```

## Database Node — Good

```text
4 vCPU
16 GB RAM
150+ GB NVMe
high IOPS
```

## Database Node — Better

```text
8 vCPU
32 GB RAM
200+ GB NVMe
```

You do NOT need the better versions immediately.

---

# 12. CPU Type

ARM is acceptable.

D8N already works well with Docker/Rails/PostgreSQL on ARM.

Examples:

```text
Ampere ARM64
```

are perfectly acceptable.

x86_64 is also fine.

Do not reject a good server simply because it uses ARM.

---

# 13. Network Requirements

Look for:

```text
1 Gbps networking or better
```

and generous bandwidth.

Check:

* monthly transfer limits
* outbound transfer pricing
* private networking
* firewall support
* floating IP/load-balancer support
* DDoS protection if available

---

# 14. Load Balancer

At two Rails nodes:

```text
              Load Balancer
               /         \
              ▼           ▼
          Rails #1     Rails #2
```

The load balancer should perform health checks.

If Rails #1 dies:

```text
Rails #2
```

continues receiving traffic.

Cloudflare can remain in front.

---

# 15. Stateless Rails Requirement

Rails application servers must be disposable.

Do not store:

```text
user photos
videos
important files
session state tied to disk
```

on the Rails VM.

Rails node should be replaceable:

```text
destroy Rails #2
     ↓
create new Rails #2
     ↓
deploy container
     ↓
back online
```

without losing user data.

---

# 16. Cloudflare R2

Hard production requirement.

Use for:

```text
profile photos
video uploads
message media
future user-generated media
```

Rails should store references/metadata.

R2 stores the actual files.

Do not use local ActiveStorage disk in real production.

---

# 17. useSend

Initial location:

```text
Server #3
```

Architecture:

```text
D8N worker
    ↓
useSend
    ↓
Amazon SES
    ↓
recipient
```

useSend should have:

```text
its own PostgreSQL database
Redis
```

but does not require its own physical DB server initially.

---

# 18. Redis

D8N itself should not become unnecessarily Redis-dependent.

Initially Redis is primarily needed for useSend and any component that explicitly requires it.

Shape:

```text
1–2 vCPU
2–4 GB RAM
```

is plenty for early use.

It can run on Server #3 initially.

---

# 19. Background Workers

Initially:

```text
Server #2
critical jobs

Server #3
general jobs
```

Possible jobs:

```text
email
SMS
push notifications
media cleanup
moderation processing
fraud checks
notifications
analytics events
```

When job queues begin competing with user requests:

```text
Dedicated Worker Server
```

becomes the next machine.

---

# 20. Server Scaling Order

If D8N becomes slow:

DO NOT GUESS.

Measure.

## Rails CPU high

Add:

```text
Rails #3
```

## Job queue growing

Add:

```text
Worker #1
```

## Database slow

First:

```text
query optimization
indexes
PgBouncer
connection tuning
```

Then upgrade:

```text
DB CPU
RAM
NVMe capacity
```

## Read traffic eventually overwhelming primary

Then consider:

```text
PostgreSQL read replica
```

---

# 21. PostgreSQL Replica

NOT required on Day 1.

Later architecture:

```text
                  PostgreSQL PRIMARY
                  writes + critical reads
                           │
                           ▼
                     READ REPLICA
```

Potential replica workloads:

```text
reporting
some discovery reads
analytics
admin aggregate queries
```

A replica can also become part of a future failover strategy.

---

# 22. Backups

This is required before meaningful production migration.

Minimum:

```text
nightly backup
```

Better:

```text
WAL / continuous backup
```

Store backups somewhere separate from the DB server.

Examples:

```text
R2
S3
other secure object storage
```

Most important:

**Test restoration.**

A backup that has never been restored is not yet proven.

---

# 23. Monitoring

Install before claiming capacity.

Monitor:

## Rails

```text
CPU
RAM
requests/sec
p50
p95
p99
error rate
Puma queue
```

## PostgreSQL

```text
CPU
RAM
connections
query latency
slow queries
locks
disk usage
IOPS
```

## Workers

```text
queue depth
failed jobs
processing time
```

## Realtime

```text
WebSocket connections
disconnect rate
reconnect rate
```

---

# 24. Error Tracking

Use:

```text
Sentry
```

or equivalent.

Never leak:

```text
passwords
tokens
private messages
PII
```

into logs.

---

# 25. Deployment

Use:

```text
Docker
Kamal
GitHub Actions
```

Target deployment:

```text
push
 ↓
CI
 ↓
tests
 ↓
build
 ↓
deploy Rails #1/#2
 ↓
health checks
```

No Kubernetes initially.

---

# 26. Capacity Expectations

These are planning numbers, NOT guarantees.

With:

```text
DB:
2 vCPU / 12 GB

Rails #1:
2 vCPU / 12 GB

Rails #2:
2 vCPU / 12 GB
```

and well-designed Rails/Postgres:

```text
100–500 active concurrent
→ should be comfortable

500–1,000
→ primary comfortable target

1,000–1,500
→ very plausible

1,500–2,500
→ monitor closely / tune

2,500–5,000
→ prove via load testing and expect additional capacity

5,000+
→ plan horizontal app scaling
```

These are not promises.

Actual capacity depends on:

```text
query quality
indexes
request rate
message rate
discovery complexity
WebSocket usage
worker load
Puma configuration
DB latency
```

---

# 27. Capacity Certification Targets

D8N should formally test:

## Gate A

```text
250 active concurrent
```

Must be trivial.

## Gate B

```text
500 active concurrent
```

Must be comfortable.

## Gate C

```text
1,000 active concurrent
```

Initial production capacity certification.

## Gate D

```text
2,500 active concurrent
```

Find and remove bottlenecks.

## Gate E

```text
5,000 active concurrent
```

Major D8N scale certification.

## Gate F

```text
10,000 active concurrent
```

Next-generation capacity milestone.

---

# 28. 5,000-User Target Architecture

Likely something more like:

```text
                         USERS
                           │
                           ▼
                      Cloudflare
                           │
                           ▼
                     Load Balancer
                /          │          \
               ▼           ▼           ▼
          Rails #1     Rails #2     Rails #3
               \           │           /
                \          │          /
                     PgBouncer
                         │
                         ▼
                  Strong PostgreSQL

                Worker #1 / #2
                       │
                       ▼
                       R2
```

Exact server count will be determined by testing.

---

# 29. 10,000-User Target

Likely:

```text
multiple Rails nodes
dedicated worker capacity
strong PostgreSQL primary
possibly read replica
PgBouncer
cache where measurements justify it
dedicated realtime infrastructure if necessary
```

Still no automatic requirement for Kubernetes or dozens of microservices.

---

# 30. Admin Console

D8N requires an internal operating console.

It should expose authorized views for:

```text
Founder
Owner
CTO
Admin
Operator
Moderator
Support
Growth
Finance
Contractor
```

It should answer:

```text
How many users joined?
Who is active?
How many are online?
Which locations are growing?
What is gender balance?
Are messages working?
How many matches occurred?
Where is onboarding failing?
Which campaigns convert?
What are reports/scam levels?
What are servers doing?
What is revenue?
What is spend?
```

It accesses D8N through controlled admin APIs.

Do not give contractors unrestricted DB access.

---

# 31. Security Basics

Every server:

```text
SSH keys only
firewall
automatic security updates where safe
minimal open ports
secrets outside Git
monitoring
audit logging
```

Database:

```text
private access only
```

Admin:

```text
MFA
RBAC
audit log
session expiration
```

---

# 32. Provider Shopping Order

## First Choice

Try:

```text
Oracle Johannesburg
```

especially where valid free capacity exists.

## If Buying Rails in Johannesburg

Search for providers offering:

```text
Johannesburg / South Africa

4 vCPU
8–16 GB
SSD/NVMe
reasonable bandwidth
```

## Tools / Automation

Hetzner is acceptable even outside South Africa because:

```text
n8n
OpenClaw
useSend
```

do not sit inside every user-facing DB transaction.

---

# 33. What to Ask a Provider

When shopping, ask/check:

```text
Where exactly is the datacenter?
How many vCPUs?
Dedicated or shared CPU?
How much RAM?
SSD or NVMe?
How much storage?
Bandwidth included?
Outbound traffic cost?
Private networking?
Load balancer available?
Snapshots?
Backups?
IPv4 included?
DDoS protection?
ARM or x86?
Monthly price?
Hourly price?
Can I resize later?
```

---

# 34. Quick Shopping Card

When browsing providers, compare every candidate against:

## APP SERVER

**Minimum**

```text
2 vCPU
8 GB RAM
SSD
JHB
```

**Target**

```text
4 vCPU
8–16 GB RAM
NVMe
JHB
```

---

## DB SERVER

**Minimum**

```text
2 vCPU
12 GB RAM
100 GB SSD
JHB
```

**Target**

```text
4 vCPU
16 GB RAM
150–200 GB NVMe
JHB
```

---

## INTERNAL TOOLS

**Minimum**

```text
2 vCPU
4 GB
```

**Target**

```text
4 vCPU
8 GB
```

Location flexible.

---

# 35. Immediate Procurement Goal

Acquire/provision:

```text
SERVER #1
Database
Johannesburg
2 vCPU / 12GB minimum

SERVER #2
Rails
Johannesburg
2 vCPU / 8–12GB minimum

SERVER #3
Rails + useSend
Johannesburg
2 vCPU / 8–12GB minimum
```

Preferred if paying:

```text
DB:
4 vCPU / 16GB

Rails:
4 vCPU / 8–16GB

Rails:
4 vCPU / 8–16GB
```

---

# 36. Immediate Execution Order

1. Secure DB server.
2. Secure Rails #1.
3. Secure Rails #2.
4. Configure private networking.
5. Configure firewalls.
6. Install PostgreSQL.
7. Configure PgBouncer.
8. Configure automated backups.
9. Configure Cloudflare R2.
10. Deploy D8N Rails #1.
11. Deploy D8N Rails #2.
12. Configure load balancing.
13. Install monitoring/error tracking.
14. Configure SES.
15. Deploy useSend.
16. Connect D8N email adapter.
17. Test registration verification.
18. Test password reset.
19. Configure SMS.
20. Configure push notifications.
21. Begin capacity testing at 250 users.
22. Progress through 500 → 1,000 → 2,500 → 5,000.

---

# 37. Final Architecture Principle

D8N should be:

**cheap to start**

without being:

**cheaply architected.**

We start with:

```text
1 dedicated DB
2 Rails-capable nodes
R2
SES/useSend
SMS
Push
```

Then capacity expands through:

```text
more Rails
more workers
stronger PostgreSQL
read replicas when justified
```

rather than rewriting the platform.

The objective is not to own the most servers.

The objective is:

**users should not notice when D8N grows.**
