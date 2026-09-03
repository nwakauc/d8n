# Date9ja Capability Parity Matrix

Audited 2026-09-02 across the Date9ja API, web client, mobile client, jobs, notifications, Action Cable channels, and D8N routes/domains. This document is the single source of truth for the normalized retained user-capability inventory and its status totals. A capability is not expendable because D8N does not support it today. **Full retained Date9ja feature parity is a production cutover requirement.**

## Scope rule

Every shipped/reachable Date9ja user-facing capability is inside the parity bar unless the product owner explicitly retires it. Community, Dating Hub, Aunty Phobie, Careers, and Feedback are included. Founder/admin operations are not consumer parity rows; they are tracked in the operational dependency register below and must map to D8N HQ before the legacy administration backend is retired.

| Capability | Date9ja today | D8N today | Parity status | D8N target domain | Brand-specific policy? | Data migration required? | API compatibility required? | Cutover blocker? |
|---|---|---|---|---|---:|---:|---:|---:|
| Registration | Email signup, attribution, welcome flow | Password registration primitive | PARTIAL | Identity | Yes | Yes | Yes | Yes |
| Password login | Devise email/password JWT | D8N password login/session | DIFFERENT SEMANTICS | Identity | Yes | Yes | Yes | Yes |
| Logout | JWT revoke/sign out | Brand session destroy | DIFFERENT SEMANTICS | Identity | No | No | Yes | Yes |
| Password reset | Email token/code reset | D8N recovery/reset | PARTIAL | Identity | Yes | No | Yes | Yes |
| Email confirmation | Devise confirmable | Identifier verification/OTP | PARTIAL | Identity/Verification | Yes | State only | Yes | Yes |
| Phone verification | Custom OTP with throttling | D8N phone OTP challenge | PARTIAL | Identity/Verification | Yes | Verified state | Yes | Yes |
| Account recovery/reactivation | Password-confirmed deletion and recovery behavior | D8N recovery/reactivation primitives | PARTIAL | Identity | Yes | Lifecycle state | Yes | Yes |
| Deactivate/delete account | Soft deletion plus hard-delete job | Brand closure/deactivation, media purge | DIFFERENT SEMANTICS | Identity/Trust/Media | Yes | Yes | Yes | Yes |
| Session persistence | Web localStorage/JWT; mobile SecureStore/JWT | Brand-scoped opaque sessions; browser cookie option | DIFFERENT SEMANTICS | Identity | Yes | No | Yes | Yes |
| Profile onboarding | Progressive user-column onboarding | Server-owned profile configuration | PARTIAL | Profiles | Yes | No | Yes | Yes |
| Profile editing | `/me` updates broad user fields | Profile and preference endpoints | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Completion score/steps | Source completion score and client steps | D8N completion contract | PARTIAL | Profiles | Yes | State | Yes | Yes |
| Public profile | User serializer and profile card | Explicit public profile serializer | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Private identity fields | Name/email/phone fields | Platform identity and owner serializer | PARITY | Identity/Profiles | Yes | Yes | Yes | Yes |
| Gender | Integer enum on user | Profile field/catalogue | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Interested-in/orientation | Integer enum on user | Profile preference field | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Relationship intent | Enum plus values/timeline | DateZA-style catalog only; Date9ja absent | MISSING | Profiles/Match | Yes | Yes | Yes | Yes |
| Faith | Onboarding field and user value | No complete Date9ja contract | MISSING | Profiles | Yes | Yes | Yes | Yes |
| Ethnicity | Onboarding field and user value | No complete Date9ja contract | MISSING | Profiles | Yes | Yes | Yes | Yes |
| Tribe | Onboarding field and user value | No complete Date9ja contract | MISSING | Profiles | Yes | Yes | Yes | Yes |
| Genotype | Sensitive onboarding field and user value | No equivalent; privacy/architecture decision required | NEEDS PRODUCT DECISION | Profiles/Trust & Safety | Yes | Yes | Yes | Yes |
| Denomination | Onboarding field and user value | No complete Date9ja contract | MISSING | Profiles | Yes | Yes | Yes | Yes |
| Preferred tribes | Matching preference array | No complete Date9ja contract | MISSING | Matching/Profiles | Yes | Yes | Yes | Yes |
| Family/children preferences | Columns/enums and onboarding data | Partial typed options | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Lifestyle fields | Smoking, drinking, fitness, education, height/body type | Partial profile fields/options | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Languages/interests/values | Arrays on users | Catalog/options/prompts | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Relocation preferences | Country array and boolean | No complete Date9ja contract | MISSING | Profiles/Match | Yes | Yes | Yes | Yes |
| Profile prompts/about | Persona/about/ideal partner and prompts | Generic prompts, no Date9ja catalog | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Profile visibility/publication | `profile_hidden`, moderation and confirmation rules | Profile publication/visibility policy | DIFFERENT SEMANTICS | Profiles/Trust | Yes | Yes | Yes | Yes |
| Profile photos | Six photos, primary/order, moderation | Profile photos, processing, visibility | PARTIAL | Media | Yes | Yes | Yes | Yes |
| Profile video | Upload/update/delete and moderation | Shared `media.profile_video.*` capability; owner CRUD + processing + **public delivery on profile detail** (ADR 0023, ADR 0011 delivery recheck); legacy importer + media reconciliation pending | PARTIAL | Media | Yes | Yes | Yes | Yes |
| Profile location | Stored coordinates/city and discovery distance | Private profile location/place model | DIFFERENT SEMANTICS | Profiles/Discovery | Yes | Yes | Yes | Yes |
| Search | Filtered `/search` endpoint | DateZA/Find/discovery surfaces differ | DIFFERENT SEMANTICS | Discovery | Yes | No | Yes | Yes |
| Discovery/daily picks | Daily picks, explore, impressions, limits | D8N discovery/find allocations | PARTIAL | Discovery | Yes | Maybe | Yes | Yes |
| Online/recent activity | Online-now endpoint and last active | Session-derived status fields | PARTIAL | Engagement/Discovery | Yes | No | Yes | Yes |
| Recommendations | Daily introductions and matching service | D8N discovery strategies | PARTIAL | Discovery/Match | Yes | Maybe | Yes | Yes |
| Pass/unpass | Pass and undo pass | Pass, no source-equivalent undo contract | PARTIAL | Match | Yes | Yes | Yes | Yes |
| Rewind | One-per-day rewind of the last discovery action | No source-equivalent rewind contract | MISSING | Match/Discovery | Yes | Yes | Yes | Yes |
| Profile view | View profile and persist view | No persisted profile views | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Like/unlike | Direct user relationships | Profile-scoped likes | PARTIAL | Match | Yes | Yes | Yes | Yes |
| Super-like | Enhanced like action and entitlement/limit behavior | No Date9ja-equivalent action contract | MISSING | Match/PAY | Yes | Yes | Yes | Yes |
| Incoming/outgoing likes | Separate list surfaces | Incoming/outgoing D8N routes | PARTIAL | Match | Yes | Yes | Yes | Yes |
| Match creation | Canonical user pair on mutual like | Canonical profile pair | DIFFERENT SEMANTICS | Match | Yes | Yes | Yes | Yes |
| Unmatch | Existing match behavior | D8N unmatch | PARTIAL | Match | Yes | Yes | Yes | Yes |
| Blocks | User block list/create/delete | Profile blocks with relationship cleanup | DIFFERENT SEMANTICS | Trust & Safety | Yes | Yes | Yes | Yes |
| Profile reports | Profile report categories/status | Profile/content reports and audit | PARTIAL | Trust & Safety | Yes | Yes | Yes | Yes |
| Message reports | Message report | D8N target-based report | PARTIAL | Trust & Safety | Yes | Yes | Yes | Yes |
| Match conversations | Match doubles as chat container | First-class conversation/participants | DIFFERENT SEMANTICS | Messaging | No | Yes | Yes | Yes |
| Text messages | Match-scoped CRUD | Conversation-scoped messages | PARTIAL | Messaging | Yes | Yes | Yes | Yes |
| Media messages | Image/video/voice Active Storage attachments | Message attachments with processing | PARTIAL | Media/Messaging | Yes | Yes | Yes | Yes |
| Message edit/delete | Edit/delete endpoints and soft deletion | D8N message lifecycle | PARTIAL | Messaging | Yes | Yes | Yes | Yes |
| Reply-to messages | Reply ID/snapshot | Same-conversation reply | PARTIAL | Messaging | No | Yes | Yes | Yes |
| Read/unread messages | Per-message `read_at` | Per-participant `last_read_at` | DIFFERENT SEMANTICS | Messaging | Yes | Yes | Yes | Yes |
| Message reactions | Emoji create/delete | No reaction model | MISSING | Messaging | No | Yes | Yes | Yes |
| Realtime messages | Action Cable match channel | D8N messaging/realtime not equivalent | PARTIAL | Messaging | Yes | No | Yes | Yes |
| Typing/presence | Cable/client behavior where implemented | No equivalent documented contract | MISSING | Messaging/Engagement | Yes | No | Yes | Yes |
| In-app notifications | Notification inbox, unread state, read actions | Brand notification events/inbox | PARTIAL | Notifications | Yes | Yes | Yes | Yes |
| Email notifications | Notification email delivery and preferences | Brand delivery plans/state | PARTIAL | Notifications | Yes | Yes | Yes | Yes |
| Push notifications | Device push delivery and preferences | Brand delivery plans/state | PARTIAL | Notifications | Yes | State | Yes | Yes |
| Notification preferences | Product/email JSON preferences | Typed product email/push preferences | PARTIAL | Notifications | Yes | Yes | Yes | Yes |
| Push registration | Token register/unregister | Encrypted brand device registration | PARTIAL | Notifications | Yes | State | Yes | Yes |
| Notification realtime/toasts/sounds | Notification Cable, UI badges/sounds | D8N notification foundation; client work required | PARTIAL | Engagement/Notifications | Yes | No | Yes | Yes |
| Email delivery state | Delivery status/retry fields | D8N delivery state | PARTIAL | Notifications | Yes | Maybe | Yes | Yes |
| Phone/SMS delivery | Verification and notification SMS | OTP/provider foundation | PARTIAL | Notifications/Identity | Yes | No | Yes | Yes |
| Selfie verification | Upload/status/admin review | No equivalent consumer verification workflow | MISSING | Verification | Yes | Yes | Yes | Yes |
| Video verification | Upload/status/admin review | No equivalent workflow | MISSING | Verification | Yes | Yes | Yes | Yes |
| Government-ID/RealMe | Submission/status/provider review | No equivalent full evidence workflow | MISSING | Verification | Yes | Yes | Yes | Yes |
| Verification badges/tiers | Numeric tier and verified UI | Contact identifier verification only | MISSING | Verification/Trust | Yes | Yes | Yes | Yes |
| Verification events/history | Checks/events/evidence retention | No equivalent full history | MISSING | Verification | Yes | Yes | Yes | Yes |
| Trust XP/score | Trust score endpoint, ledger, adjustments | No equivalent persisted trust capability | MISSING | Trust & Safety | Yes | Yes | Yes | Yes |
| Moderation/publication | Admin flags, photo review, suspensions/bans | Profile/photo moderation and enforcements | PARTIAL | Trust & Safety | Yes | Yes | Yes | Yes |
| Community questions | Browse/create questions and report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community answers | Browse/create answers and report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community answer votes | Vote/unvote answers | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community events | Browse/create events and remarks | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community event RSVP/attendees | RSVP and attendee visibility | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community stories | Browse/create stories and report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community story remarks | Browse/create remarks and report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community moderation | Admin review/risk flags/reports | No D8N community moderation | MISSING | Community/Trust & Safety | Yes | Yes | Yes | Yes |
| Dating Hub batches | CRUD dating-workflow batches | No D8N equivalent | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Dating Hub tracked contacts | Matched and external contact tracking | No D8N equivalent | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Dating Hub contact notes | Notes attached to tracked contacts | No D8N equivalent | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Dating Hub suggestions | Contact-specific suggestions | No D8N equivalent | MISSING | Engagement/AI | Yes | Yes | Yes | Yes |
| Dating Hub coach | Coach content and guidance | No D8N equivalent | MISSING | AI | Yes | Yes | Yes | Yes |
| Dating Hub persona | User-configured dating persona | No D8N equivalent | MISSING | AI/Profiles | Yes | Yes | Yes | Yes |
| Dating Hub daily-life journal | Daily life entry CRUD | No D8N equivalent | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Aunty Phobie conversation | AI assistant messages/support | No D8N equivalent | MISSING | AI | Yes | Yes | Yes | Yes |
| Aunty Phobie history/usage limits | Conversation history, usage events, limits | No D8N equivalent | MISSING | AI/PAY | Yes | Yes | Yes | Yes |
| Aunty Phobie escalation | Safety escalation/admin resolution | No D8N equivalent | MISSING | AI/Trust & Safety | Yes | Yes | Yes | Yes |
| Premium/founding access | Premium status, founding membership/limits | No Date9ja billing/entitlement target | MISSING | PAY/Entitlements | Yes | Yes | Yes | Yes |
| Signup acquisition attribution | First-touch UTM/source captured at signup | D8N analytics event model differs | PARTIAL | Insights | Yes | Maybe | Yes | No |
| Product analytics events | Signup/profile/verification/match/conversation metrics | D8N analytics event model differs | PARTIAL | Insights | Yes | Maybe | Yes | No |
| Support chat | Dedicated support account via match/messages | No explicit D8N support-chat capability | MISSING | Messaging/Support | Yes | Yes | Yes | Yes |
| Careers | Public jobs, applications, and application status | No Date9ja careers target | MISSING | Community/Operations | Yes | Yes | Yes | Yes |
| Feedback | User feedback submission and status | No Date9ja feedback target | MISSING | Engagement/Support | Yes | Yes | Yes | Yes |

## Counts — authoritative

| Status | Count |
|---|---:|
| PARITY | 1 |
| PARTIAL | 42 |
| MISSING | 40 |
| DIFFERENT SEMANTICS | 11 |
| LEGACY/UNUSED | 0 |
| NEEDS PRODUCT DECISION | 1 |
| **Total** | **95** |

Delta log: Profile video MISSING → PARTIAL (2026-09-02) — shared `media.profile_video.*` capability built (ADR 0023); owner CRUD + processing only; not PARITY until the importer, media reconciliation, and the acceptance journey pass.
Delta log: Profile video public delivery wired (2026-09-02) — `Profiles::DetailSerializer` now exposes a `video` payload on `GET /api/v1/profiles/{id}` for brands that enable `profile.video` (Date9ja), re-authorized per read via `Profiles::VideoLibrary` + `Media::VideoPolicy` (ADR 0011). Codex-reviewed 2026-09-02 (VERIFIED) with a `ProfileVideo.brand_id == Profile.brand_id` defence-in-depth guard added. Still PARTIAL — legacy video importer, migrated-media reconciliation, sanitized snapshot, and the frontend/API + parity acceptance journeys remain (see `SNAPSHOT-RUNBOOK.md`).

Delta log: Profile video legacy importer — pass 1 (media preflight) VERIFIED (Codex independent review 2026-09-03: ACCEPT WITH SMALL FIX — documentation correction completed) — `Date9ja::Snapshot::VideoSource` + `Date9ja::Import::VideoPreflight` reuse the generic `Migration::MediaObjectRef` / `MediaAttachmentRef` / `ReferenceMap` spine (no new framework). Sanitized-snapshot rehearsal: 35/35 preflighted, idempotent second pass, 0 `ProfileVideo` / 0 Active Storage rows, content types 26 `video/mp4` + 9 `video/quicktime` (0 unsupported); legacy `duration_seconds` missing for all 35 → no source row known to exceed the D8N limit, actual duration unproven, pass 2 must derive it from the media container. **Status unchanged — still PARTIAL** (pass-2 byte transfer + L2 synthetic-corpus rehearsal, migrated-media reconciliation, and the frontend/API + parity acceptance journeys remain).

The detailed inventory and these counts are authoritative. Other migration documents must link here rather than copy totals. The normalization split independently migratable user capabilities and excludes founder/admin operations from the consumer scoreboard.

## Normalization record

- Split bundled rows for gender/orientation, sensitive profile fields, pass versus rewind, like versus super-like, notification channels, Community primitives, Dating Hub primitives, Aunty Phobie history/limits, and analytics versus acquisition attribution.
- Reclassified Careers and Feedback from the former bundled `LEGACY/UNUSED` row into explicit retained capabilities because reachable web/mobile/API surfaces exist in the source repository.
- Reclassified Support chat from `NEEDS PRODUCT DECISION` to an engineering-owned missing capability; only a material user-visible behavior change returns to the product queue.
- Removed the former `account UI` implementation-detail bundle; account settings and lifecycle behaviors are represented by their distinct capability rows.

## D8N AI ownership

`D8N AI` is the shared platform capability: provider abstraction, assistant runtime, context, safety, privacy/egress, credentials, versioning, metering, limits, tools, and failure handling. `Aunty Phobie` is a Date9ja branded assistant experience consuming that runtime. They are intentionally not one matrix row and no `domains/date9ja/aunty_phobie` implementation is authorized. The AI architecture/specification gate and third-party data-egress decision must pass before implementation reaches `IMPLEMENTING`.

## Operational dependency register (excluded from consumer counts)

| Legacy operational surface | D8N destination | Retirement requirement |
|---|---|---|
| Moderation, reports, photo/video/selfie review | D8N HQ / Trust & Safety | HQ can perform equivalent brand-scoped review and audit |
| User suspension, bans, deletion/recovery operations | D8N HQ / Identity lifecycle | HQ workflows preserve authorization, audit, and recovery controls |
| Acquisition, metrics, error logs, backups | D8N HQ / Insights / Operations | Required operational reports and backup evidence exist |
| Community/Dating Hub/Aunty escalation administration | D8N HQ with shared-domain admin policies | Operators retain safe workflows for active retained capabilities |
| Careers and Feedback review | D8N HQ / Support operations | Review, notification, retention, and export responsibilities are assigned |

These rows do not reduce the user parity bar and are not counted as Date9ja consumer capabilities.

## Source evidence used for normalization

The reachability review used Date9ja API controllers/models/jobs/channels plus the web and mobile clients, including `api/app/controllers/api/v1/careers_controller.rb`, `feedback_items_controller.rb`, `message_reactions_controller.rb`, `dating_hub/*`, `community/*`, `aunty_phobie_controller.rb`, `profile_views_controller.rb`, `profile_videos_controller.rb`, and `config/routes.rb`; web `src/pages/CareersPage.js`, `CommunityPage.js`, `DatingHubPage.js`, `AuntyPhobiePage.js`, `ProfileViewsPage.js`, `MessagesPage.js`, and `src/api/client.js`; and the mobile navigation/API surfaces. These are source-repository observations only; no production usage counts were accessed.
