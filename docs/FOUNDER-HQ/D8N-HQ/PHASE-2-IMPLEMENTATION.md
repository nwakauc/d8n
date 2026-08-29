# D8N HQ — Phase 2 Backend Implementation (Trust & Safety Command Surface)

Status: **BACKEND BUILT; PHASE PARTIAL.** The backend contract and
verification are complete. The canonical Phase 2 frontend work,
frontend verification, security launch gate, and end-to-end slice
acceptance remain outstanding. This document is the frontend handoff for
the shipped backend; `docs/api/openapi.yaml` (tag `Hq`) is the
machine-readable source of truth.

## Roadmap scope implemented

Phase 2's existing backend scope is implemented without a migration:

- current-brand report queue counts, breakdowns, and oldest-open aging;
- bounded repeat-offender aggregation;
- cursor-paginated brand-wide enforcement history;
- reuse of the existing report queue, report detail/evidence, report
  lifecycle, suspension, and reinstatement APIs;
- links from repeat-offender/enforcement results into Phase 1 Member 360;
- server-derived brand authorization and sensitive-read auditing.

No APM, observability vendor, support ticketing, new RBAC, cross-brand
super-admin, frontend, SLA policy, case-management model, migration, or
new moderation write path was added.

## Backend routes

### New Phase 2 reads

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/api/v1/hq/trust_safety/overview` | Queue/enforcement snapshot for the current brand |
| GET | `/api/v1/hq/trust_safety/repeat_offenders` | Bounded list of profiles with at least two received reports |
| GET | `/api/v1/hq/trust_safety/enforcements` | Newest-first, brand-wide enforcement history |

### Existing moderation routes reused by Phase 2

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/api/v1/admin/reports` | Oldest-first report queue; optional `status`, `cursor`, `limit` |
| GET | `/api/v1/admin/reports/{id}` | Audited report detail with bounded immutable evidence snapshot |
| PATCH | `/api/v1/admin/reports/{id}` | Existing report lifecycle transition |
| POST | `/api/v1/admin/profiles/{profile_id}/suspension` | Existing brand-level suspension |
| DELETE | `/api/v1/admin/profiles/{profile_id}/suspension` | Existing brand-level reinstatement |

The HQ backend does not duplicate these mature admin services. Frontend
may present them in one Trust & Safety page while calling their existing
routes.

## Authentication, authorization, and brand context

- Accepts the existing opaque bearer session or host-only browser session.
- Request host resolves `Current.brand`; no endpoint accepts `brand_id`.
- Caller must be an authenticated `User` linked to a kept, active
  `AdminUser` with a kept, active `AdminAssignment` for that exact brand.
- Missing/invalid/wrong-brand session: `401`.
- Authenticated ordinary user or admin assigned elsewhere: `403`.
- Current authorization remains role-name-blind and uses the existing
  `moderator` assignment. Frontend must not infer capabilities from a
  role label.
- There is no platform-wide or "All D8N" member-data query.

## Trust & Safety overview contract

`GET /api/v1/hq/trust_safety/overview` has no parameters. It returns:

- `brand`, `generated_at`;
- reports `total`;
- stable `by_status` keys (`open`, `reviewing`, `actioned`, `dismissed`),
  including zero values;
- `awaiting_decision` (`open` + `reviewing`);
- `oldest_open_report_at` and `oldest_open_report_age_seconds`, both null
  when there is no open report;
- stable `by_reason` and `by_target_type` maps, including zero values;
- `sla_status: "not_configured"` and `overdue: null`;
- total and active enforcement counts.

The null overdue value is intentional. The canonical plan explicitly
defers a real SLA until an approved threshold/policy exists; the backend
does not manufacture one.

Safe abbreviated response:

```json
{
  "overview": {
    "brand": "hookus",
    "generated_at": "2026-08-29T15:00:00Z",
    "reports": {
      "total": 12,
      "by_status": { "open": 3, "reviewing": 1, "actioned": 5, "dismissed": 3 },
      "awaiting_decision": 4,
      "oldest_open_report_at": "2026-08-28T12:00:00Z",
      "oldest_open_report_age_seconds": 97200,
      "sla_status": "not_configured",
      "overdue": null
    },
    "enforcements": { "total": 4, "active": 1 }
  }
}
```

## Queue and filter behavior

The canonical queue remains `GET /api/v1/admin/reports`:

- current brand only;
- oldest first by `(created_at, id)`;
- optional `status`: `open`, `reviewing`, `actioned`, `dismissed`;
- optional signed opaque `cursor`;
- optional `limit`, default 25, range 1–100;
- invalid filter/cursor/limit: `422`;
- response: `{ reports: [...], next_cursor: string|null }`.

Reason and target-type counts are available in the overview, but the
queue does not yet accept reason or target-type filters. Frontend must
not fake client-side completeness across paginated data.

## Report detail and evidence behavior

Use `GET /api/v1/admin/reports/{id}`. It returns the existing explicit
`AdminReport` schema, including the immutable, bounded `evidence` snapshot
captured when the report was filed. It may contain only the target-specific
evidence defined by ADR 0018 (for example the reported message or bounded
conversation window). It is not a general conversation browser.

Unknown and cross-brand IDs return the same neutral
`report_unavailable` (`404`). The read records `admin.report_viewed`.
Emails, phone numbers, credentials, sessions, private location, raw media,
and unrestricted conversation history are omitted.

## Repeat-offender behavior

`GET /api/v1/hq/trust_safety/repeat_offenders` accepts optional `limit`
(default 25, range 1–100).

- A repeat offender is a profile that has received at least two retained
  reports in the current brand, regardless of final report status.
- This is a triage signal only; it never changes a report or account.
- Ordering: report count descending, latest report descending, internal
  profile ID ascending as deterministic tie-breaker.
- Each row returns public `profile_id`, public `display_name`,
  `report_count`, `awaiting_decision_count`, `latest_report_at`, and
  `member_360_lookup`.
- `member_360_lookup` is null when a retained historical profile has been
  soft-deleted and Member 360 deliberately cannot resolve it.
- The result is bounded, not cursor-paginated. `truncated: true` means more
  qualifying profiles exist.
- Invalid limit: `422 invalid_limit`.

## Enforcement-history behavior

`GET /api/v1/hq/trust_safety/enforcements` accepts:

- `state` (optional): `active` or `reverted`;
- `cursor` (optional): opaque signed cursor;
- `limit` (optional): default 25, range 1–100.

Rows are newest-first by `(created_at, id)` and reuse the established
`AdminEnforcement` schema. The cursor is bound to the current brand and
the selected state, and cannot be replayed against another brand/filter.
Invalid state, limit, or cursor returns `422` with `invalid_filter`,
`invalid_limit`, or `invalid_cursor`.

## Member 360 integration

- Repeat offender: navigate with `member_360_lookup` when non-null.
- Enforcement: navigate with `profile_id` when non-null.
- Destination: `GET /api/v1/hq/members/{lookup}`.
- Report detail: `reported.id` and `reporter.id` are profile public IDs
  and can be used as Member 360 lookups when those profiles remain kept.
- A neutral `404 member_unavailable` is an expected historical/deleted or
  wrong-brand state and must render as unavailable, not trigger a broader
  cross-brand search.

## Error and empty-state matrix

| Situation | HTTP/result | Frontend behavior |
| --- | --- | --- |
| No data | `200` with zero maps/empty arrays/null oldest timestamp | Render an explicit empty state |
| Missing/invalid session | `401` | Re-authenticate; do not retry indefinitely |
| Not an assigned moderator | `403 forbidden` | Render forbidden; do not infer another role |
| Unknown/cross-brand report | `404 report_unavailable` | Render unavailable without existence claims |
| Invalid filter/limit/cursor | `422` stable error code | Reset offending filter/cursor and show recoverable validation state |
| Unexpected server/database failure | `5xx` standard API failure | Preserve current UI state and offer manual retry; never substitute zeros |

## Privacy and audit behavior

New successful reads emit one `SecurityEvent` each:

- `hq.trust_safety_overview_viewed`;
- `hq.trust_safety_repeat_offenders_viewed`;
- `hq.trust_safety_enforcements_viewed`.

Audit rows identify the acting admin user and brand. Only the optional
enforcement `state` filter is added as metadata; no evidence, notes,
reasons, search text, contact identifiers, or member PII are copied into
the audit event. Existing report detail and moderation writes retain
their existing audited behavior.

## Performance and loading expectations

- Overview uses bounded grouped/count/min queries over the current brand.
- Reports have brand/status/created-at, brand/target-type/created-at, and
  brand/reported-profile indexes.
- Repeat offenders performs one brand-scoped aggregate, one bounded
  profile load, and one bounded awaiting-decision count query; maximum
  100 rows are serialized.
- Enforcement history is keyset-paginated and loads at most `limit + 1`.
- Frontend should load the overview first, then queue/repeat-offender/
  enforcement panels independently so one slow or failed panel does not
  blank the page.
- Never fetch all report pages to compute client-side totals; overview is
  the authoritative snapshot.

## Known limitations and deliberately unavailable behavior

- No approved SLA threshold; overdue remains unavailable.
- No reports-per-1,000 metric is computed ad hoc; that canonical metric
  belongs in the Phase 5 metric registry/rollup work.
- Repeat offenders are bounded and not cursor-paginated.
- No reason/target-type queue filter.
- No case/investigation timeline model.
- No general message/conversation viewer.
- No verification-review surface because product verification does not exist.
- No cross-brand rollup or platform-level admin grant.
- No new moderation write path; writes remain under `/api/v1/admin`.
- No frontend was implemented in this backend slice.

## Frontend acceptance criteria

The canonical roadmap did not assign Phase 2 frontend HQ-Fxx IDs; do not
invent them during integration. Phase 2 frontend work is accepted when an
assigned moderator can, for one host-resolved brand:

1. see real queue counts, breakdowns, oldest-open age, and explicit
   `SLA NOT CONFIGURED` state;
2. browse the existing oldest-first queue and its supported status filter;
3. open audited report detail/evidence without exposing omitted PII;
4. identify repeatedly reported profiles and deep-link to Member 360;
5. browse/filter/page enforcement history and deep-link to Member 360;
6. use the existing report transitions and suspension/reinstatement flows;
7. see intentional loading, empty, forbidden, unavailable, validation,
   and retry states;
8. prove cross-brand isolation in frontend integration tests.

Before frontend implementation, read `D8N-HQ-PLAN.md`, `ROADMAP.md`, this
document, `SECURITY-AND-RBAC.md`, and `docs/api/openapi.yaml`, plus the
supplied D8N HQ visual reference.
