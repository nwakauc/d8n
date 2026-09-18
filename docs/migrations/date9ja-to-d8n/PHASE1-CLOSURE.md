# Date9ja cutover Phase 1 — September 18, 2026

State: **NOT READY FOR FINAL PRODUCTION REHEARSAL**. Engineering changes below
are SELF_VERIFIED within their stated scope; independent review and full-family
acceptance remain outstanding. Historical READY labels are superseded.

No deployment, production import/data repair, media write/delete, source freeze,
DNS/routing switch or Vercel configuration change was executed. Production
inspection and a read-only backup were authorized. Raw backups stay unchanged;
protected local artifacts must never enter git or an issue body.


## Latest raw snapshot received — September 18 follow-up

The owner supplied `/Users/uchechinwaka/Downloads/backups_db_production_20260918030000.dump`.
It remains unchanged and unsanitized. SHA-256:
`961c779038b030b39565143f32dc0f3b02b13ed2f6c6916321b393c3a7c150fe`.
Archive metadata: September 18, 2026 03:00 SAST; api_production; PostgreSQL 16.14.
Restore succeeded in isolated `date9ja_phase1_source_20260918`.

Compared with the raw September 15 source: 944 total users, 898 eligible,
46 deleted, zero banned, seven eligible suspended. Eleven users added and
65 existing user rows changed (includes operational fields; not all are profile
edits). Added: 116 likes, 161 passes, five matches, 60 messages; 23 existing
messages changed. Photos: 14 added, three removed. Videos: three added.
Verification checks: six added, four changed; 13 verification events added.
Trust events: 35 added. Attachment/blob tables: 23 added, seven removed each.
These are raw source differences, not import-success claims or eligible-family
reconciliation results. Detailed source-key manifests are private and outside git.

Field-level comparison of existing users found no changed active email, phone,
password digest, ban/deletion/suspension fields or gender/looking-for values.
There are three changed recovery-token/timestamp pairs, one pending email change,
two verification-tier changes, two religion-preference changes, two tribe-
preference changes, one profile hide and three trust-XP changes. Recovery tokens
are not migrated as valid D8N challenges; members must use D8N recovery. Pending
email changes must not silently replace the current authentication identity.

The latest backup prerequisite is now satisfied for engineering rehearsal.
Writes after 03:00 SAST still need final freeze-time capture; this file is not
proof that production stayed unchanged after its snapshot. Full-family sync and
media/evidence gates remain open. Previous references below to a missing latest
backup describe the earlier phase and are superseded by this receipt.

## Changes and preservation of yesterday's work

- Preserve the configured HookUs no-location discovery policy and 30-minute
  activity window. Shared-engine tests now request the default distance policy;
  the stale-session fixture lies outside the configured activity window.
- Preserve ADR 0010 history reads after unmatch. Request tests retain denial of
  new messages and attachment uploads and assert that denied sends add no rows.
- Freeze the location-search burst test's clock so its requests cannot straddle
  the real limiter's fixed window. No production limiter policy was changed.
- Reconstruct platform User/email/phone/password-credential references through
  an already-bound Profile and its brand presence, validated against the
  restored baseline's identifiers. Never locate/merge users by email globally.
  Reference ownership remains NULL for platform destinations, per ADR 0022.
- Add a separate explicit membership-reference correction boundary. Normal
  ReferenceMap immutability is unchanged. A protected preview plan captures
  exact prior mappings; application rejects stale plans, locks mappings and
  atomically reclaims only the attested membership mappings. Domain rows stay
  untouched. Production application is forbidden.
- Disable both unsafe PK-copy promotion scripts. They exit 64 without connecting
  to a database. IDs of new destination rows come from destination sequences;
  foreign keys use stable source-system/entity/ID reference bindings.
- Add a normalized baseline/final bundle synchronizer with an explicit field
  allowlist, one transaction, a parameterized per-brand advisory lock, preview
  rollback, semantic adoption of identical native events, conflict aborts,
  password children, option selections and conversation participants.
- Replace bucket-wide byte transfer with reviewed Date9ja manifest entries,
  bounded streaming SHA-256 verification, conditional create-only writes and
  nonzero CLI exit on any required failure. Existing objects require complete
  byte verification; equal length is insufficient. No list/delete/overwrite.
- Treat ENETUNREACH as a transient mail transport failure, with no raw provider
  exception data exposed. Resend configuration itself is preserved.
- Frontend: validate incoming browser origin/fetch metadata before any unsafe
  proxy request, then establish server-controlled Origin/fetch context for D8N.
  Host/forwarded headers cannot expand the server's allowlist. Preserve cookies,
  CSRF headers, HttpOnly/SameSite attributes and private/no-store responses.
- Frontend: preserve the existing hidden pause/delete controls, per the product
  owner's September 18 correction. Backend lifecycle adapters remain in place.

## Actual production-cohort reference proof (isolated clone)

A read-only September 18 D8N primary backup was restored into new isolated local
rehearsal databases. The unchanged September 15 raw legacy backup was restored
into a separate isolated source. This proves the reference mechanism for the
existing cohort; it is NOT proof of final source freshness or production repair.

The first attempt stopped on a membership discrepancy. Investigation found all
887 Profile→membership→User spines valid, but **two legacy membership bindings
pointed at the wrong IDs** (one of those destinations is absent). The explicit
repair plan corrects those mappings on the clone; no membership is recreated.

| Family | Before missing | After bindings | Distinct destinations | NULL ownership |
|---|---:|---:|---:|---:|
| User | 885 | 887 | 887 | 887 |
| Email identity | 885 | 887 | 887 | 887 |
| Password credential | 885 | 887 | 887 | 887 |
| Previously imported phone identity | 621 | 623 | 623 | 623 |
| Valid source phone after explicit omitted-identity repair | 1 missing identity | 624 | 624 | 624 |

One source phone is unparseable and remains explicitly excluded. The other
omitted phone is valid and source-verified: its Date9ja user had no phone, while
another brand had the same normalized value on a different platform identity.
The existing independent per-brand identity policy (commit f624b6d) permits this.
An explicit protected plan created exactly one Date9ja phone identity on the
already-bound Date9ja user, without linking the other-brand identity or user.
There are now 624 valid source phone bindings, all platform-owned NULL references
with distinct destinations. Its second application created zero identities;
other-brand fingerprints remained unchanged. Email/password bindings for the
entire cohort reconcile. A same-brand collision still fails closed.

After reference reconstruction: domain counts unchanged, no new User/identity/
credential/membership/profile/password-hash rows; the second repair adds zero
mappings. The subsequent explicit phone repair is the one intentional local
identity creation described above, not a duplicate or account merge.
The repeat proof eagerly loads models before fingerprinting, and all other-brand
rows remain unchanged. The first fingerprint attempt had an invalid comparison
because lazy-loaded models changed the registry; its false result was discarded
and the complete proof repeated on a fresh restore.

Protected backup, SQL restore and repair-plan artifacts remain in /private/tmp
with private permissions. They contain sensitive data and are not report
attachments. Production still has its original mappings until separately
authorized, reviewed operator application.

## Synchronization conflict policy

Bundles must come from independently normalized snapshot A and fresh snapshot B,
not from current native destination state masquerading as the original baseline.
No MAX(ID) watermark. No raw destination PK/FK copied from staging. Unknown fields,
unbound dependencies, missing baselines and unexplained omissions abort atomically.

| Family | Policy |
|---|---|
| Platform User | Existing binding only; no account merge. Shared-user name edits abort if another brand has joined. Date9ja profile edits remain brand-local. |
| Email/phone identities | Three-way comparison; source-only changes allowed through the bound Date9ja identity. Dual edits or uniqueness collisions abort. Foreign-key reassignment forbidden. |
| Credentials/password hashes | Hash changes only when destination still equals baseline; native recovery survives unchanged source; dual password changes abort. Missing hashes/timestamps fail closed; revoke Date9ja credential sessions after change. |
| Membership/profile/preferences | Apply source-only field changes; retain native-only fields; dual edits abort. Native restrictions and soft deletion are never relaxed by source activation. |
| Catalog selections | Compare complete code pairs per profile. Source-only changes replace only bound profile selections via soft deletion; native changes with unchanged source survive; dual changes abort. |
| Photos/videos | Bound scalar/moderation changes and attested soft removals can be reconciled. New media is rejected with media_graph_required: attachment/blob/checkpoint synchronization is NOT complete. No R2 deletion. |
| Likes/passes/blocks | Stable source references. Identical semantic native event may be adopted; a different native event conflicts instead of duplicating/overwriting. |
| Matches/conversations/unmatches | Canonical destination pair order; semantic native adoption only if identical. Native ended state cannot be relaxed. Ensure correct brand-scoped conversation participants. |
| Messages/reactions | Stable source references; append new records, preserve native records. Native read acknowledgements/deletion retained. Dual body/reaction edits abort. Existing attachments remain untouched; historical attachment promotion remains open. |
| Reports/moderation | Source-only bound changes; dual native review/enforcement edits abort. Restrictive membership state revokes Date9ja sessions, not other-brand sessions. |
| RealMe | Bound assertion state may change only through three-way comparison; native review conflicts abort. No fabricated approvals. Evidence attachment runtime mapping remains open. |
| Trust | Append-only awards/adjustments, stable idempotency keys; existing award changes abort and require reviewed compensating events. Never rewrite native ledger awards or replace a native score wholesale. |
| Lifecycle/tombstones | Missing rows alone are not deletions. Explicit source_deleted/source_banned attestation required for removed profiles; preserve platform identity, restrict Date9ja membership, hide/soft-delete brand presence, end interactions and revoke Date9ja sessions. Retain source bindings to prevent resurrection. |
| Notification/history archives | Only bound Date9ja history rows; runtime notification history conversion requires the product decision below. Native notification rows are untouched. |
| Paid entitlements | No Billing/Subscription/Entitlement write surface exists in this synchronizer. Never infer payment from founding/seed/admin flags. Preserve actual legacy benefits only through an approved brand entitlement mapping. |

The automated A→B test imports identity and preferences, starts with another
brand's records, adds native biography/preference edits and a native conversation/
message, changes source profile/preference/catalog/password/hide/suspension,
adds a new legacy user with usable credentials, like and message, adopts the
identical native match/conversation, then synchronizes twice. Rerun makes zero
new/updated rows/password hashes and preserves native data and other-brand rows.
Separate tests cover atomic dual-edit abort, preview rollback, numeric FK rejection,
unexplained omission, deletion/brand isolation, unchanged-source native recovery/
pause/hide/unmatch, append-only trust and fail-closed new media.

**Limit:** this is representative automated proof, not the requested complete
production-scale A→B media/moderation/RealMe/fresh-source rehearsal. The two facts
must not be conflated. The normalized raw-source compiler, attachment/checkpoint
promotion and full family reconciliation still require closure.

## Media differences and evidence

No production transfer or delete was run. The audit's differences remain open:
one eligible source photo, ten eligible source videos, two failed imported videos,
24 historical message attachments and required current verification evidence.
Code fixes do not establish the availability or safety of those bytes.

The September 18 raw source was then inventoried through explicit eligible
owners, without bucket enumeration. Read-only source R2 HEAD requests verified
all 1,521 objects: 1,021 photo attachments, 163 profile videos, 23 non-deleted
message attachments, 188 selfie attachments and 126 verification-check evidence
attachments. All sizes and ETag MD5 metadata match the snapshot. This is actual
source availability evidence; it is not a full-byte SHA-256 proof or destination
runtime-readiness claim. Evidence retention selection remains required.

Comparing that inventory with the isolated production clone gives **15 missing
photo bindings, 13 missing video bindings, two not-ready imported videos and 23
missing live-message attachments**. The remaining historical attachment belongs
to one source-deleted message (24 total); preserve its tombstone and do not make
its attachment accessible. These latest counts supersede the older source's
one/ten gaps and include new additions. Three removed source photos also require
explicit three-way removal reconciliation, without deleting healthy R2 objects.

Full streamed source GET checks subsequently verified all **53 gap-associated
objects, 226,653,768 bytes**, against snapshot MD5 and exact size, and recorded
SHA-256 receipts in a private artifact. Zero missing/corrupt/failed objects in
that set. No bytes were uploaded, overwritten or deleted. This proves source
byte integrity for those gaps, not completed D8N attachment/runtime promotion.

The two not-ready imported videos were also read and processed locally using
the unchanged Media::VideoProcessor. Both produced validated H.264 playback and
nonempty posters (approximately 9.58 and 10.5 seconds). No database changes or
R2 writes occurred. This proves real-source local processing is viable; it does
not change their production processing state or establish the old failure cause,
which has no recorded processing_failure_reason on these two rows.

Isolated September 15 raw restore confirms attachment families: Message 24,
Photo 1,052, ProfileVideo 161, SelfieVerification 191, VerificationCheck 128.
These are SOURCE attachment counts, not eligible/imported/accessible counts.
Deleted/banned member exclusions, message visibility and evidence retention rules
must be applied before a required ownership manifest is accepted. Expired
verification/government-ID evidence must not be restored indiscriminately.

Manifest schema (protected JSON): version=1, brand=date9ja, objects containing
kind (photo/video/message_attachment/verification_evidence), source_id,
source_key, destination_key, positive byte_size and lowercase SHA-256. Every
entry is required. Review ownership, retention and canonical key mapping first;
SHA-256 must come from trusted source bytes, not unverified destination metadata.
The transfer never enumerates a bucket. Unclassified existing objects stay alone.

Tests prove same-length/different-content destination corruption fails without
an overwrite, bad/missing/oversized source fails before writing, copied bytes
verify, second run verifies without writing, invalid/duplicate manifest fails,
and the CLI exits 1 on an actual required-object failure.

Evidence levels: replacement transfer **CODE TESTED**; actual legacy-source R2
availability and gap byte integrity **REAL PRODUCTION READ-ONLY VERIFIED**;
the two real-source video playback/poster outputs **LOCAL PROCESSING VERIFIED**.
Existing D8N referenced-media health was read-only audit evidence. Complete
attachment/evidence promotion and final R2 synchronization have NOT been claimed
REHEARSAL VERIFIED or REAL PRODUCTION READY.

## BFF and lifecycle proof

Nine frontend proxy tests cover accepted same-origin register/login/reactivation,
rejected foreign-origin versions, missing/cross-site metadata, spoofed host and
CSRF/cookie forwarding. Seven Date9ja Rails integration tests confirm canonical
trusted context is accepted at the actual auth endpoints, foreign context is
rejected and trusted context cannot bypass CSRF. These are local tests, not live
production authentication smoke tests.

The UI regression test verifies pause/delete controls remain hidden even when
the backend advertises support, with no lifecycle action or logout invoked. The
earlier exposed-control UI tests were superseded by the product owner's explicit
visibility instruction. Existing full-suite tests
cover pause/reactivation, closure, deleted-user non-resurrection and other-brand
membership/profile/session/device preservation. Full browser journeys after an
approved deployment remain operator acceptance work.

## Email diagnosis and acceptance

Current production selects Resend, has a configured key and Date9ja sender
`Date9ja <no-reply@date9ja.love>`. Message rendering produced nonempty HTML/text.
No secrets or recipients were printed and no production email was sent.

Two failed queue executions on September 14 were DeliverChallengeJob and
DeliverProductNotificationJob, both Errno::ENETUNREACH. This previously escaped
the transport's transient-error classification; the regression is fixed/tested.
This is exact evidence for those job failures, not an explanation of all 11
permanent delivery errors.

The 11 email deliveries record Resend validation_error with only a generic
message; the original rejection detail was intentionally not retained. The exact
historical provider root cause is therefore unproven. A read-only GET /domains
returned restricted_api_key: the production sending key cannot inspect domains.
The product owner's September 18 09:19:59 screenshot confirms date9ja.love is
currently **Verified** in Resend. The screenshot shows it was newly created;
that does not prove the precise reason for each September 14 rejection.

Operator acceptance after an explicitly approved deployment, before traffic:
use controlled synthetic inboxes to register/verify, request password recovery
and confirm new-password login, then trigger one product notification. Require
correct Date9ja sender/branding, provider acceptance AND inbox delivery, one
message per idempotent delivery, working challenge, zero credential/PII logging
and healthy queue completion. Do not retry mail to real members automatically.

## Product classification — proposed, approval required

No category-B feature has been silently retired by this work.

| Capability | Proposed category | Required decision/handling |
|---|---|---|
| Existing authentication/credentials | A | Preserve all eligible accounts, normalize without merges; quarantine collisions explicitly. |
| Profiles/preferences/photos | A | Preserve values and visibility, verify required safe derivatives. |
| Conversations/messages, matches/likes/passes/blocks/unmatches | A | Usable history, attachment access, correct unread state and interaction denial after safety changes. |
| Reports/moderation/current RealMe/current trust | A | Preserve current facts/enforcement and operator access to required evidence. |
| Deletion/ban/suspension/hide/pause | A | No resurrection; restrict Date9ja presence and preserve other brands. |
| Registration/onboarding/discovery/new messaging/lifecycle/email verification/recovery | A | Complete new and existing-user acceptance journey. |
| Legacy notification inbox history | B | Archive rather than runtime inbox only with explicit approval and a tested retained-access policy. Native D8N inbox unaffected. |
| AI conversation history | B | Explicit private archive/retention/access decision; no automatic runtime reconstruction. |
| Community history | B | Explicit archive/relaunch decision; existing public/member content must not disappear without notice. |
| Profile views | B | Archive history or approve retirement; present/current product behavior separately accepted. |
| Daily introduction history | B | Archive prior introductions; new recommendations are a separate current feature decision. |
| Explore impressions | B | Retain approved analytics archive; no member feature loss hidden as analytics cleanup. |
| Exit-attempt history | B | Archive operational reasons; preserve core pause/delete regardless of retirement of win-back prompts. |
| Verification transition history | B for old transitions; A for current state/evidence | Preserve operator/legal history under retention policy; archive current transition UI only with approval. |
| Rewind | B | Explicit retirement/availability decision; preserve pass/unlike state and do not infer approval. |
| Online/activity indicators | C for enhancements; B for legacy exact semantics | Accept the implemented 30-minute activity policy explicitly; historical online UI retirement needs approval. |
| Voice messages | A for usable retained messages; B for new composing | Existing voice attachments need secure playback or an explicitly accepted alternative; new composer retirement needs approval. |
| Message edit/delete/reactions | A for stored edits/deletions/reactions; B for composing actions | Do not expose deleted content; approve any retirement of new edit/delete/reaction actions. |
| Old mobile-client API compatibility | A if released clients exist | Require compatibility or an approved, enforced transition before changing the API they use. |
| Founding-member behavior | A for existing benefits; B for future automatic awards | Legacy User#premium_access? and mobile accessGuards grant founding access. Preserve 470 snapshot flags/approved benefits; never invent paid subscriptions. |

A = must preserve for cutover. B = potentially safe to archive/retire only after
explicit product approval. C = post-cutover enhancement. Proposed B/C labels
are not permission to remove existing behavior.

## Mobile evidence and recommendation

**COMPATIBILITY LAYER REQUIRED** as the conservative cutover requirement until
release evidence proves there are no deployed legacy clients or product approves
an enforced transition. Compatibility was not implemented in this phase.

Repository app version is 1.0.0, iOS build 4, Android versionCode 6. EAS preview
and production profiles both select https://api.date9ja.love/api/v1. Git tag v1
exists. Repository/build configuration establishes intended production API, not
proof of an App Store/Play Store release or installed population. Store/EAS
release history remains unverified.

Legacy mobile calls /auth/sign_up, /auth/sign_in, /auth/sign_out (nested user
credentials and legacy token contract), /me PATCH, confirmation/password routes,
photos/profile_video, daily_picks/search/online_now, profile like/pass/rewind/
block/report, matches/:id/messages multipart and read, messages edit/delete/
reactions, notifications and legacy verification routes. These differ from D8N
password register/login/reactivation and conversation-based media endpoints.
An existing client using that configuration would break if the API host were
switched without compatibility/transition. New untracked mobile candidate code
also retains legacy API adapters; it is not proof of a D8N-native release.

## Current automated gate results — September 18 follow-up

| Gate | Current result |
|---|---|
| `RAILS_ENV=test bin/rails test` via rbenv | **2,481 runs, 27,424 assertions, zero failures/errors/skips**; seed 49699 |
| `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bin/rubocop --no-server` via rbenv | **1,045 files, zero offenses** |
| `bin/brakeman --no-pager` via rbenv | **zero security warnings, zero errors** |
| `RAILS_ENV=test bin/rails zeitwerk:check` via rbenv | **All is good** |
| Frontend Vitest, Node 22 | **35 files, 186 tests passed** |
| Frontend configured `next lint`, Node 22 | **No ESLint warnings or errors** |
| Frontend TypeScript `tsc --noEmit --incremental false`, Node 22 | **Passed** |
| Frontend isolated production build, Node 22 | **Passed; 35 pages generated** |

Failures encountered during validation were not hidden: the broad-suite
location-search burst flake was fixed by freezing its clock; the configured
limiter is unchanged. An exploratory `eslint .` incorrectly traversed generated
Next artifacts and mobile dependency trees and failed; the repository's actual
`next lint` command passes. Ruby runs with the stale BUNDLE_PATH override failed
dependency discovery, and Node 20 could not load the current Vite toolchain;
checks above use installed rbenv gems and Node 22. Local libvips plugin and
duplicate-key JSON warnings remain disclosed below. None is counted as a passed
command.

No D8N commit was created in this session; changes remain reviewable in the
working tree. The frontend now has a separately created commit `a38d279`, which
includes the BFF and hidden-controls regression files alongside mobile work;
this session did not create that commit or deploy it. Existing unrelated D8N
plan edits and HookUs SQL artifacts were preserved.

The runtime profile-photo/video upload adapters, processing jobs, storage
configuration and existing healthy production media were not changed. The new
byte-transfer class/script is a migration operator tool, not the live upload
path. Production upload writes were deliberately not exercised in this phase;
read-only object checks do not substitute for post-deployment upload acceptance.

## Open cutover gates

P0:
1. Finish the normalized raw-source final-bundle compiler and attachment/blob/
   checkpoint/evidence synchronization; prove every required family, including
   media additions/removals and current moderation/RealMe changes, on populated
   destination A→B→B while retaining native activity. Existing prototype rejects
   new media intentionally. Verification: expanded FinalSync suite plus full
   fresh-source family reconciliation and byte receipts.
2. Capture writes after the received September 18 03:00 SAST raw backup during
   the eventual authorized write freeze. The received file is restored and
   hashed, and satisfies the engineering source prerequisite. It does not
   capture subsequent live writes. Verification: final freeze-time backup/delta,
   raw-source census, baseline/final comparisons and zero unexplained differences.
3. Resolve missing media, two failed videos, 24 historical attachments and
   retained verification evidence with ownership/retention manifest and safe
   derivatives. Verification: SHA-256 read receipts, runtime attachment access,
   no unexplained missing required objects, second run zero writes.
4. Obtain product decisions on founding benefits, legacy mobile transition and
   proposed retirements. Preserve existing benefits/history by default. Verify
   entitlement and released-client journeys without granting paid subscriptions.
5. Independent review required by docs/engineering/AGENT-WORKFLOW.md before
   VERIFIED/PARITY_ACCEPTED. Production repair/rehearsal/deployment require their
   own later authorization; no production operator command is enabled here.
6. Prove a Date9ja-only rollback that retains native Date9ja writes after the
   switch and all other-brand writes. Restoring an old full shared D8N database
   would lose other products' activity and is not an acceptable rollback.
   Verification: isolated switch/write/rollback rehearsal, export/reconcile new
   Date9ja writes, and unchanged other-brand fingerprints.

P1: exact old Resend validation messages still need provider logs; synthetic
verification/recovery/product delivery is operator acceptance before traffic;
full frontend new/migrated/admin browser acceptance remains to run.

P2: local libvips HEIF plugin reports missing libx265 (tests still pass);
pre-existing duplicate-key JSON test warnings should be cleaned up separately;
future full notification/community/AI history UX depends on product decisions.

## Isolated commands (not production commands)

Use RAILS_ENV=test and DATABASE_URL naming a new d8n_date9ja_rehearsal_* database.
DATE9JA_SNAPSHOT_DATABASE_URL must name a separately restored scratch legacy DB.
Never supply a production URL under a test environment.

1. Hash the untouched raw backup, inspect pg_restore --list metadata and restore
   into a fresh scratch source; restore a read-only D8N backup into a separate
   fresh destination clone. Use compatible PostgreSQL clients. Keep artifacts
   private, outside git. Validate migrations/schema before mutation.
2. Preview membership corrections with DATE9JA_MEMBERSHIP_REFERENCE_PLAN_OUTPUT:
   `bin/rails runner scripts/date9ja/repair_membership_references.rb`.
3. Review the protected plan. On the isolated clone only, set
   DATE9JA_MEMBERSHIP_REFERENCE_REPAIR_APPLY=true and
   DATE9JA_MEMBERSHIP_REFERENCE_PLAN to that exact file; repeat the same command.
4. Preview `bin/rails runner scripts/date9ja/repair_references.rb`; apply on the
   clone only with DATE9JA_REFERENCE_REPAIR_APPLY=true. Reconcile and repeat;
   required second-run missing counts are zero for imported eligible families.
   For omitted valid phones, preview with DATE9JA_PHONE_IDENTITY_PLAN_OUTPUT and
   `bin/rails runner scripts/date9ja/repair_phone_identities.rb`; review the
   protected plan, then use DATE9JA_PHONE_IDENTITY_REPAIR_APPLY=true and
   DATE9JA_PHONE_IDENTITY_PLAN on that same isolated clone. Repeat and require
   zero new identities and unchanged other-brand fingerprints.
5. Export independently normalized A/B staging bundles using
   DATE9JA_SYNC_OUTPUT and `bin/rails runner scripts/date9ja/export_sync_bundle.rb`.
   Export is exclusive-create, mode 0600. Include explicit removal attestations.
   Stop if media graph/current source compiler gates are unresolved.
6. Set DATE9JA_SYNC_BASELINE/DATE9JA_SYNC_DESIRED; preview
   `bin/rails runner scripts/date9ja/final_sync.rb`. Only on a fresh clone, set
   DATE9JA_SYNC_APPLY=true. Reconcile every family and native/other-brand
   fingerprints. Repeat identical inputs; require zero unintended mutations.
7. Reviewed isolated media manifest only:
   `ruby scripts/date9ja/transfer_media_bytes.rb`. Requires explicitly supplied
   source/destination configuration and DATE9JA_MEDIA_MANIFEST. Stop on nonzero
   exit; never use this phase to write production R2.
8. Run the four required backend gates and frontend tests/types/lint/build.
   Complete new user, migrated user and HQ acceptance on the isolated stack,
   including cross-brand denial, lifecycle and current verification evidence.

Do not proceed to production rehearsal, deployment or traffic changes from this
report. The open P0s above must first be closed and reviewed.
