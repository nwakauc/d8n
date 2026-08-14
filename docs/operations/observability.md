# Minimum Production Observability

## Current proven signals

- `GET /up` proves that a Rails process booted. It does not query dependencies.
- `GET /api/v1/health` returns `200` only when both the primary and Solid Queue
  PostgreSQL connections answer; otherwise it returns a bounded `503`.
- Production logs go to standard output and include the Rails request ID.
- Rails filters passwords, email, phone, secrets, tokens, OTP/code values,
  cryptographic fields, and precise coordinates from parameter logs.
- Solid Queue persists ready, scheduled, claimed, blocked, and failed execution
  state in its separate PostgreSQL database.

These are primitives, not a complete monitoring system. No error-tracking or
uptime provider is configured yet.

## Small beta signal set

Configure one error tracker and one external uptime check after the founder
selects providers. Keep the first dashboard/alerts limited to:

| Signal | Initial purpose |
| --- | --- |
| `/up` availability | Detect a web process that cannot boot/respond |
| `/api/v1/health` availability | Detect primary or queue DB unavailability |
| HTTP 5xx count/rate and p95 latency | Detect application regressions/saturation |
| PostgreSQL CPU, connections, disk, slow queries | Detect the measured first bottleneck |
| Solid Queue failed count and oldest ready-job age | Detect poison/stalled work |
| Host/container CPU, memory, disk | Detect resource exhaustion |
| R2 request failures and media-job failures | Required only when media is activated |

Alert thresholds must be calibrated from staging and early beta behavior. Do not
page on every validation error or add distributed tracing before evidence demands
it.

## Queue checks

An authorized operator can inspect bounded operational counts without reading job
arguments:

```sql
SELECT count(*) FROM solid_queue_failed_executions;

SELECT count(*) AS ready_jobs,
       min(created_at) AS oldest_ready_at
FROM solid_queue_ready_executions;

SELECT kind, count(*)
FROM solid_queue_processes
GROUP BY kind;
```

Never export serialized job arguments to metrics or alerts; they may contain user
or provider identifiers.

## Privacy boundary

Do not send passwords, bearer/session tokens, OTPs, private messages, photo bytes,
signed media URLs, storage keys, exact coordinates, verification payloads, or
unnecessary profile/relationship data to logs, analytics, metrics, or exception
contexts. Prefer opaque record IDs, brand ID, bounded error code, operation name,
duration, and request ID. Scrub request headers and job arguments before enabling
an external error tracker.

## Staging proof required

Before DR-06 is Done, record a dated staging exercise proving:

1. an external check detects `/up` failure;
2. a controlled dependency failure makes `/api/v1/health` alert without exposing
   connection details;
3. a controlled failed job appears in the queue alert and can be inspected;
4. an application exception reaches the selected tracker with filtered request
   parameters and no bearer token;
5. the operator can correlate the alert, application log, and request ID.

