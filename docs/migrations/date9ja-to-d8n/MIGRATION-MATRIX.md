# Migration Matrix

Compatibility: **direct** = equivalent target semantics; **transform** = target exists but values/ownership/shape change; **contract gap** = target exists but client/product contract differs; **missing** = no target capability. Any `legacy-only`/`can wait` wording below is historical Phase 0 classification and is superseded by the retained-capability rule in [`CAPABILITY-PARITY.md`](CAPABILITY-PARITY.md): no shipped user capability may be silently discarded. Operational founder/admin records are excluded from consumer counts but remain retirement dependencies mapped to D8N HQ.

| Date9ja source | Purpose | D8N destination | Compatibility | Transformation required | Risk | Action |
|---|---|---|---|---|---|---|
| `users` identity/profile/lifecycle | account and dating presence | `users`, `identity_identifiers`, `brand_memberships`, `profiles` | transform | split identity/profile; normalize identifiers; map lifecycle | high | external-ID import and explicit state policy |
| `users.encrypted_password` | password credential | `credentials` + `credential_password_hashes` | transform, likely direct | copy bcrypt string; bind to normalized email | critical | prove against sanitized snapshot |
| confirmation fields | email verification | email identifier `verified_at` | transform | preserve verified state/timestamp; discard live tokens | high | map state, invalidate tokens |
| `phone_verifications` / phone state | phone verification | phone identifier `verified_at` | transform | E.164 normalize; import verified state only | high | reconcile duplicates/invalid numbers |
| `users.jti`, JWT/session state | API sessions | `sessions` | incompatible | issue fresh brand-scoped sessions | high | one-time re-login |
| profile/gender/preferences/relationship fields | dating profile | `profiles`, preferences, options, prompts | transform | map enums/arrays into typed capabilities and stable options | high | value census and approvals |
| precise lat/lng/city/country | location/discovery | `profile_locations`, `places`, profile country/city | transform | keep exact location private; map coarse place | high | validate freshness/ranges |
| hidden/suspended/banned/deleted fields | lifecycle/moderation | membership/profile status, enforcements, closures | transform | distinguish inactive, sanctioned, deleted, unpublished | critical | approved state map |
| `photos` + Active Storage | photos/order/primary/review | `profile_photos` + D8N media storage | transform | profile ownership, position, status, object mapping | critical | checksum/object preflight |
| `profile_videos` | profile video | no equivalent profile-video target | missing | **HISTORICAL/SUPERSEDED:** legacy-only or separately approved feature; current target is shared Media/Profile Video | high | never convert silently |
| `likes` | positive interaction | brand `likes` | transform | user→profile, kind/timestamps | high | same-brand unique direction |
| `profile_passes` | negative interaction | brand `profile_passes` | transform | user→profile, timestamps | medium | report exclusions explicitly |
| `matches` | mutual interest | brand canonical `matches` | transform | profile pair canonicalization/status | critical | unique pair + mutual-like check |
| implied match chat | chat container | `conversations` + participants | transform | one conversation per retained match, two participants | critical | graph validation |
| `messages` | content/read/edit/delete | brand `messages` | transform | match→conversation, sender→profile, reply/read mapping | critical | stable ordering and quarantine |
| message attachments | voice/image/video media | `message_attachments` | contract gap | map object/type/metadata; process under D8N | critical | broken/unsupported exception report |
| `message_reactions` | emoji reactions | no current target | missing | **HISTORICAL/SUPERSEDED:** legacy-only/export; current target is shared Messaging/Reactions | medium | never discard; target required |
| `blocks` | safety exclusions | `profile_blocks` | transform | user→same-brand profile, direction/timestamp | critical | no self/cross-brand rows |
| `reports` | reports/moderation | `reports`, enforcements, security events | transform | map category/status/reviewer/target | critical | preserve unresolved reports |
| `audit_logs` | admin/security history | `security_events` where compatible | transform/legacy-only | **HISTORICAL/SUPERSEDED:** structured safe event mapping; archive remainder only where not required by D8N HQ | high | retain original evidence |
| verification/selfie/video/ID records | identity evidence | no equivalent full evidence target | missing/contract gap | status/history only if approved; evidence likely archive | critical | legal/privacy decision |
| `push_tokens` | device registration | `device_registrations` | transform | membership, encrypted token/digest, platform | high | re-register if semantics differ |
| `notifications` | inbox/read state | notification events + notifications | transform | map supported types/payload/read state | medium | quarantine unsupported; no replay |
| `notification_deliveries` | delivery state | `notification_deliveries` | transform | map status/channel; suppress old pending sends | high | historical only |
| notification preference JSON | opt-outs | `notification_preferences` | transform | map known product email/push preferences | medium | preserve explicit opt-outs |
| `profile_views` | view history | no current target | missing | **HISTORICAL/SUPERSEDED:** legacy-only/export; current target is shared Engagement/Profile Views | medium | product visibility decision plus target required |
| subscription/premium fields | entitlement | no current billing target | missing | **HISTORICAL/SUPERSEDED:** legacy-only or approved bridge; current target is PAY/Entitlements | critical | product retention and engineering target required |
| trust events/adjustments/xp | trust score/history | no equivalent trust ledger | missing | secure archive or approved import | high | never infer sanctions from score |
| daily introductions/explore impressions | discovery history | find/discovery allocations | contract gap | map only if semantics are approved | medium | avoid stale allowance import |
| `dating_hub_*`, contacts, personas, daily life | product tools | no target | legacy-only | **HISTORICAL/SUPERSEDED:** archive/export or separate migration; current target is decomposed shared primitives | medium | architecture specification required |
| `aunty_phobie_*` | AI support/usage | no target | legacy-only | **HISTORICAL/SUPERSEDED:** archive under privacy policy; current target is D8N AI plus Date9ja assistant definition | high | egress/retention decision required |
| `community_*` | community content | no current brand community domain | legacy-only | **HISTORICAL/SUPERSEDED:** legacy read-only/separate migration; current target is shared Community | medium | do not silently discard |
| careers/company/feedback/errors | operations/company | no Date9ja core target | legacy-only | **HISTORICAL/SUPERSEDED:** operational archive for company/admin records; Careers and Feedback user surfaces are retained capabilities | low/medium | map operations to D8N HQ; do not hide user features |
| variants | derived media | D8N processing | contract gap | regenerate where safe; retain originals | medium | compare deliverability |

Every missing or historically legacy-only row requires a D8N target, an explicit product-approved retirement, or a supported transition that preserves user access. Nothing is silently discarded. This matrix preserves source→destination mapping evidence; `CAPABILITY-PARITY.md` owns user-capability scope and totals.
