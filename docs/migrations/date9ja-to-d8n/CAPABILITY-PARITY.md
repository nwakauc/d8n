# Date9ja Capability Parity Matrix

Audited 2026-09-02 across the Date9ja API, web client, mobile client, jobs, notifications, Action Cable channels, and D8N routes/domains. The inventory contains **75 user-facing capability rows**. A capability is not expendable because D8N does not support it today. **Full retained Date9ja feature parity is a production cutover requirement.**

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
| Gender/interested-in | Integer enums on user | Profile/preference fields | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Relationship intent | Enum plus values/timeline | DateZA-style catalog only; Date9ja absent | MISSING | Profiles/Match | Yes | Yes | Yes | Yes |
| Faith/ethnicity/tribe/genotype | Columns, arrays, onboarding JSON | Some typed/catalog capability, not complete Date9ja set | MISSING | Profiles/Verification | Yes | Yes | Yes | Yes |
| Family/children preferences | Columns/enums and onboarding data | Partial typed options | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Lifestyle fields | Smoking, drinking, fitness, education, height/body type | Partial profile fields/options | PARTIAL | Profiles/Match | Yes | Yes | Yes | Yes |
| Languages/interests/values | Arrays on users | Catalog/options/prompts | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Relocation preferences | Country array and boolean | No complete Date9ja contract | MISSING | Profiles/Match | Yes | Yes | Yes | Yes |
| Profile prompts/about | Persona/about/ideal partner and prompts | Generic prompts, no Date9ja catalog | PARTIAL | Profiles | Yes | Yes | Yes | Yes |
| Profile visibility/publication | `profile_hidden`, moderation and confirmation rules | Profile publication/visibility policy | DIFFERENT SEMANTICS | Profiles/Trust | Yes | Yes | Yes | Yes |
| Profile photos | Six photos, primary/order, moderation | Profile photos, processing, visibility | PARTIAL | Media | Yes | Yes | Yes | Yes |
| Profile video | Upload/update/delete and moderation | No profile-video capability | MISSING | Media | Yes | Yes | Yes | Yes |
| Profile location | Stored coordinates/city and discovery distance | Private profile location/place model | DIFFERENT SEMANTICS | Profiles/Discovery | Yes | Yes | Yes | Yes |
| Search | Filtered `/search` endpoint | DateZA/Find/discovery surfaces differ | DIFFERENT SEMANTICS | Discovery | Yes | No | Yes | Yes |
| Discovery/daily picks | Daily picks, explore, impressions, limits | D8N discovery/find allocations | PARTIAL | Discovery | Yes | Maybe | Yes | Yes |
| Online/recent activity | Online-now endpoint and last active | Session-derived status fields | PARTIAL | Engagement/Discovery | Yes | No | Yes | Yes |
| Recommendations | Daily introductions and matching service | D8N discovery strategies | PARTIAL | Discovery/Match | Yes | Maybe | Yes | Yes |
| Pass/unpass | Pass, unpass, rewind | Pass, no source-equivalent rewind contract | PARTIAL | Match | Yes | Yes | Yes | Yes |
| Profile view | View profile and persist view | No persisted profile views | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Like/super-like/unlike | Direct user relationships | Profile-scoped likes | PARTIAL | Match | Yes | Yes | Yes | Yes |
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
| Email/push/in-app notifications | Notifications, delivery rows, preferences | Brand notification events/inbox/deliveries | PARTIAL | Notifications | Yes | Yes | Yes | Yes |
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
| Community questions/answers/votes | Browse/create/answer/vote/report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community events/RSVP/attendees | Browse/create/remarks/RSVP | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community stories/remarks | Browse/create/remark/report | No D8N community domain | MISSING | Community | Yes | Yes | Yes | Yes |
| Community moderation | Admin review/risk flags/reports | No D8N community moderation | MISSING | Community/Trust & Safety | Yes | Yes | Yes | Yes |
| Dating Hub batches/contacts | CRUD and matched/external contacts | No D8N equivalent | MISSING | Engagement or Community | Yes | Yes | Yes | Yes |
| Dating Hub notes/suggestions | Contact notes and suggestions | No D8N equivalent | MISSING | AI/Engagement | Yes | Yes | Yes | Yes |
| Dating Hub coach/persona | Coach and persona CRUD | No D8N equivalent | MISSING | AI | Yes | Yes | Yes | Yes |
| Dating Hub daily life | Daily life entry CRUD | No D8N equivalent | MISSING | Engagement | Yes | Yes | Yes | Yes |
| Aunty Phobie chat | AI assistant messages/support | No D8N equivalent | MISSING | AI | Yes | Yes | Yes | Yes |
| Aunty Phobie escalation | Safety escalation/admin resolution | No D8N equivalent | MISSING | AI/Trust & Safety | Yes | Yes | Yes | Yes |
| Premium/founding access | Premium status, founding membership/limits | No Date9ja billing/entitlement target | MISSING | PAY/Entitlements | Yes | Yes | Yes | Yes |
| Analytics/attribution | Signup attribution, admin metrics/events | D8N analytics event model differs | PARTIAL | Insights | Yes | Maybe | Yes | No |
| Support chat | Dedicated support account via match/messages | No explicit D8N support-chat capability | NEEDS PRODUCT DECISION | Messaging/Support | Yes | Yes | Yes | Yes |
| Feedback/careers/account UI | Feedback and career application flows | Not Date9ja dating core in D8N | LEGACY/UNUSED | Community/Operations | Yes | Decision | Yes | No |

## Counts

| Status | Count |
|---|---:|
| PARITY | 1 |
| PARTIAL | 37 |
| MISSING | 24 |
| DIFFERENT SEMANTICS | 11 |
| LEGACY/UNUSED | 1 |
| NEEDS PRODUCT DECISION | 1 |
| **Total** | **75** |

The detailed inventory contains 75 capability rows. The counts above are authoritative for this document.
