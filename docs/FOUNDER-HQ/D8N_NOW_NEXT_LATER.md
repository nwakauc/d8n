# D8N — NOW / NEXT / LATER

**One-screen source of truth for where D8N is and what to build next.**
Updated: 2026-08-17. Owner: Founder. Reconciled against code, tests, routes, and git history (not from memory).

> Detailed accountable tasks live in [`TODO/`](../../TODO). Architecture rationale lives in [`docs/adr/`](../adr).
> Operational/infra state lives in [`D8N_FOUNDER_STATE.md`](D8N_FOUNDER_STATE.md). This file exists so you never
> have to read all of those to know the current critical path. When they disagree, code + this file win.

---

## Primary milestone: **HookUs Beta Ready**

A real HookUs user can: register → authenticate → onboard → build a profile → upload safe photos →
discover eligible people → filter discovery → like/pass → mutually match → open a conversation →
**exchange messages** → block/report → **manage/close their account** — and we can **moderate and operate**
that beta responsibly.

Everything else (other brands, richer discovery, marketplace, video, scaling) is explicitly *not* this milestone.

---

## Dating-loop status (verified 2026-08-17)

Legend: **GONE** = does not exist · **PARTIAL** = some code, real gap · **QA** = implemented + tested, needs staging proof · **READY** = staging-proven · **LATER** = deliberately deferred

| Capability | Status | Beta blocker | Evidence / gap |
| --- | --- | --- | --- |
| Registration / auth | QA | — | password register/login, brand-scoped sessions, verification create/update endpoints + tests |
| Password recovery (signed-out) | **GONE** | **Yes** | no reset route; `auth/passwords` is register/login/authenticated-update only → **ID-04** |
| Onboarding | QA | — | `onboarding_status`, profile configuration/options/preferences endpoints + tests |
| Profile | QA | — | show/update, options, preferences, publication, location |
| Photo upload | READY | — | direct-to-R2 intent→PUT→attach→signed GET; HTTP E2E proven on staging 2026-08-15 |
| Safe media processing | QA | — | `ProcessProfilePhotoJob` decode/re-encode/EXIF-strip/purge-raw + stranger-safe delivery; needs deploy + staging + frontend browser E2E |
| Discovery (For You) | READY | — | ranked default; staging baseline captured |
| Discovery filters | QA | — | `mode=for_you\|new_here`, `vibe`, `online`; cursor-bound; OpenAPI documented + tests |
| Like / Pass | QA | — | concurrency + canonical-match tests |
| Match | QA | — | canonical pair, atomic, concurrency-tested |
| Conversation creation | QA | — | match-gated metadata shell; block-aware |
| Messaging (text content) | QA | — | **DL-03 built 2026-08-17** — `Message` + `GET/POST …/conversations/:id/messages`, cursor history, block/suspend/brand enforcement via `ConversationAccess`; 18 tests green. Needs staging proof |
| Block / Unblock / List | QA | — | full directional block + mutual enforcement across surfaces; list added `b02f4f4` |
| Report | QA | — | create-only, idempotent per open report, audit event |
| **Admin moderation** | **GONE** | **Yes** | `AdminUser/Role/Assignment` models exist but no admin controllers/routes; reports are unreadable/unactionable → **TS-03** |
| **Suspend / ban** | **PARTIAL** | **Yes** | `suspended` status is *enforced* in matching/messaging, but no action to set it + no session revocation → **TS-04** |
| **Account closure / deletion** | **GONE** | **Yes** | soft-delete columns exist; no self-service flow, recovery window, or media-purge-on-close → **TS-06** |
| Notifications (user-facing) | **GONE** | No | only internal `NotificationDelivery` (verification email/SMS). Polling beta needs none → LATER |

---

## NOW — finish + safely operate the HookUs loop (P0)

These are the only things that genuinely stop us inviting 10–50 controlled beta users.

1. ~~**DL-03 — Persisted text messaging.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** The core loop now closes end-to-end. Remaining: DL-04 staging two-user proof.
2. **TS-03 — Minimal admin moderation review queue.** *Now the top open P0.* Users can report harm today with nobody able to see or act on it. Authorized moderators list/view/decide reports for permitted brands, with sensitive-read + decision auditing. Unblocks TS-04.
3. **TS-04 — Suspend/ban enforcement.** Once reports are reviewable, we must be able to remove a bad actor and revoke their sessions. The enforcement half already exists; the action + session-kill + audit do not. (Messaging already denies suspended users, so this composes cleanly.)
4. **TS-06 — Account closure & deletion.** EU-hosted; a user must be able to leave and have media purged. Data-protection P0 even though invisible in the happy path.
5. **ID-04 — Password recovery** and **ID-02 — registration throttling.** Users will lock themselves out; unthrottled distinct-identifier signup is an abuse hole. (ID-04 could be support-manual at 10–50 users if truly time-boxed.)

**Early-beta safety follow-up surfaced by DL-03:** message send rate-limiting (no reusable app-wide limiter exists yet; deferred deliberately — see NEXT).

## NEXT — needed as real users arrive (P1)

- **ID-03** productionize identifier verification (real email/SMS via durable jobs) — gated on external AWS SES production access (submitted 2026-08-14).
- **ID-01** E.164 phone normalization before uniqueness matters at scale.
- **DR-01/02** dedicated production topology + managed PostgreSQL (staging is healthy; production not yet stood up — deliberately sequenced *after* the product loop).
- **DR-05/06/07** backups+restore proof, external error/uptime tracking, deploy/rollback + secret-rotation drill.
- **SB-05** a green hosted CI run from clean checkout (now that `dev` is a CI trigger).
- **DL-01/02/04** the staging QA proofs that move the many **QA** rows above to **READY**.
- **DL-05** finish beta-shape load/failure testing on *dedicated* infra (not shared with Date9ja).
- **Message send rate-limiting** — lightweight per-sender throttle on `POST …/messages` (DL-03 shipped without one; document-and-defer decision).

## LATER — improve while users arrive / after beta

See [`TODO/90_later_when_justified.md`](../../TODO/90_later_when_justified.md). Do not let these interrupt NOW:
enterprise/generic RBAC, formal appeals product, WebSocket chat / presence / typing / reactions / attachments,
video & general media platform, PostGIS / precomputed recs / read replicas, Kubernetes / microservices,
user-facing MFA, Google/WebAuthn login, payments/Plus, Date9ja migration or a second brand,
Hook Tonight / Verified-only / Visiting discovery facets (need unbuilt domains).

---

## Critical-path test

For every candidate blocker ask: *"Would we genuinely refuse to let 10–50 controlled beta users into HookUs without this?"*
If no → it is not P0, even if it would improve the product. Safety, legal, data-loss, and security issues can be P0
even when invisible to users.

**Shortest path to "invite controlled beta users": ~~DL-03~~ (done) → TS-03 → TS-04 → TS-06 → ID-04/ID-02**, in parallel
with the DR/DL staging-QA proofs. Messaging (the product gate) is now built; the trust/account items are the
remaining responsible-operation gate.
