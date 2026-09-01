# D8N — NOW / NEXT / LATER

**One-screen source of truth for where D8N is and what to build next.**
Updated: 2026-09-01. Owner: Founder. Reconciled against code, tests, routes, and git history (not from memory). HQ implementation status is maintained in `D8N-HQ/CURRENT-STATE.md`.

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
| Password recovery (signed-out) | QA | — | **ID-04 built 2026-08-17** — `POST /auth/password/recovery` → `/verify` → `/reset`; verified-identifier-only, enumeration-resistant neutral `202`, single-use expiring code + reset token (reuses `OtpChallenge`/throttle/adapters), cross-brand session revocation, membership-state-preserving; 18 tests green. Needs staging proof + provider gate |
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
| Admin moderation | QA | — | **TS-03 built 2026-08-17** — `GET /admin/reports`, `GET/PATCH /admin/reports/:id`, session-based moderator auth (`admin_users.user_id` link + assignment), audited lifecycle; 17 tests green. Admin MFA still a pre-launch gate. Needs staging proof |
| Suspend / ban (brand-level) | QA | — | **TS-04 built 2026-08-17** — `POST/DELETE /admin/profiles/:id/suspension`: membership suspend + brand session revocation + `AccountEnforcement` + audit; enforced across all surfaces; 16 tests green. Platform-wide ban deferred. Needs staging proof |
| Account closure / deletion | QA | — | **TS-06 built 2026-08-17** — `DELETE /me` (brand-level): tombstone + anonymize + session revoke + matches ended + **async R2 media purge** (tracked); identity + shared/safety records retained; 18 tests green. Platform-wide identity deletion deferred (policy). Needs staging proof |
| Notifications (user-facing) | FOUNDATION | Yes | brand-scoped inbox/read API + DateZA welcome email foundation built 2026-08-21; production push/device enrollment and later event policies remain LATER |

---

## NOW — finish + safely operate the HookUs loop (P0)

These are the only things that genuinely stop us inviting 10–50 controlled beta users.

1. ~~**DL-03 — Persisted text messaging.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** The core loop now closes end-to-end. Remaining: DL-04 staging two-user proof.
2. ~~**TS-03 — Minimal admin moderation review queue.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** Moderators can list/inspect/decide reports with audit. **Admin MFA is implemented; founder enrollment and staging/production acceptance remain pre-launch gates.**
3. ~~**TS-04 — Suspend/ban enforcement.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** Brand-level suspend/reinstate with session revocation + audit; enforced across all surfaces. Platform-wide ban deferred (needs a global admin authority).
4. ~~**TS-06 — Account closure & deletion.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** Brand-level `DELETE /me` with async R2 media purge; identity + shared/safety records retained. Platform-wide identity deletion deferred (policy decision).
5. ~~**ID-04 — Password recovery.**~~ **BUILT 2026-08-17 (IMPLEMENTED + TESTED, awaiting staging proof).** Signed-out three-step verified-identifier recovery; enumeration-resistant; cross-brand session revocation; never reactivates a left/closed membership. Production delivery gated on the SMS/email provider (shared with ID-03). **ID-02 — registration throttling** is now the top open P0 code: unthrottled distinct-identifier signup is an abuse hole.

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
- **Admin MFA** — pre-launch operational gate: encrypted TOTP, recovery codes, per-session step-up, throttling, audit, and reset are implemented in the HQ backend. Founder enrollment and staging/production verification remain outstanding.
- **Admin provisioning** — Founder bootstrap and current-brand operator assignment APIs now exist. The API still requires an existing verified D8N identity and active brand membership; it does not create credentials or a Founder identity.
- **Platform-wide ban + global admin authority** — TS-04 ships brand-level suspension only; a cross-brand ban needs a deliberately-introduced global admin role. Add when a severe cross-brand safety case requires it.

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

**Shortest path to "invite controlled beta users": ~~DL-03~~ → ~~TS-03~~ → ~~TS-04~~ → ~~TS-06~~ → ~~ID-04~~ (all done) → ID-02**,
in parallel with the DR/DL staging-QA proofs + admin MFA (pre-launch gate). The trust/safety/account loop and signed-out
recovery are now built; **ID-02 registration throttling is the last P0 code**, then the DR/DL staging proofs + go/no-go.
