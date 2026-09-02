# API / Frontend Compatibility

The audited clients are Date9ja `web/` React and `mobile/` Expo/React Native. Both use bearer tokens, JSON `/api/v1`, and Action Cable; web stores tokens in local storage and mobile in Expo SecureStore.

Legacy calls include `/auth/sign_up`, `/auth/sign_in`, `/auth/sign_out`, `/auth/confirmation`, `/auth/password`, `/me`, `/photos`, `/profile_video`, `/matches`, `/matches/:id/messages`, `/messages/:id`, `/notifications`, `/blocks`, `/profiles/:id`, `/likes`, `/search`, `/profile_views`, `/verification/*`, `/community/*`, `/dating_hub/*`, `/aunty_phobie`, and admin paths.

D8N has equivalents for core identity, profile, photos, location, preferences, discovery, likes/passes, matches, conversations/messages, notifications, blocks, reports, deactivation, and recovery, but names and shapes differ. D8N uses host-resolved brand context, opaque profile public IDs, first-class conversations, `/profile/photos`, server-owned `/profile/configuration`, and `/auth/password/register|login` plus `/auth/session`.

Minimum client work: change the trusted API base; replace auth endpoints and handle fresh session issuance; map user IDs to profile/match/conversation public IDs; use server onboarding configuration; adapt photo upload/order/private URLs; adapt conversation message/read paths; and provide supported D8N paths for every extended feature before cutover. Preserve a compatibility adapter at the client boundary with version/error telemetry. A temporary server shim is acceptable only if it enforces D8N authorization and explicit serializers.

## Endpoint compatibility manifest

The web and mobile clients use the same logical endpoint set. Mobile additionally registers/unregisters push tokens and uses multipart URI uploads; web uses browser `File` uploads. The following manifest is the endpoint-level inventory extracted from both API clients and their call sites. “Adapter” means a client/server compatibility layer is practical; it does not mean the feature can be omitted.

| Legacy endpoint(s) / method | Request and response assumptions | D8N path/status | Frontend change / adapter | Realtime |
|---|---|---|---|---|
| `POST /auth/sign_up`, `/auth/sign_in`, `DELETE /auth/sign_out` | `{user: ...}`, JWT response, bearer token | `/auth/password/register`, `/auth/password/login`, `DELETE /auth/session` | Required auth adapter; preserve password, replace token/session storage | Cable token changes |
| `GET/PATCH /me`, `DELETE /account` | User-shaped profile JSON; password deletion | `GET /me`, `PATCH /me`, `DELETE /me` or account close contract | Map identity/profile response and closure semantics | No |
| `GET/POST /auth/confirmation`, `POST/PATCH /auth/password` | Devise confirmation/reset token/code | `/auth/verification`, `/auth/password/recovery*`, `/auth/password` | Map codes/status/error envelopes | Email only |
| `GET/POST /verification/phone*` | Phone/code payload and verified state | `/verification/phone`, `/verification/phone/request`, `/verification/phone/confirm` | Request/response adapter | SMS |
| `GET/POST /verification/selfie`, `/verification/video`, `/verification/government_id`, `/verification/realme` | Multipart evidence and status/tier JSON | No complete equivalent today | Must build shared Verification capability and client adapter | Admin/provider jobs |
| `GET/PATCH /profile`, `/me` profile fields | Broad user field update and user serializer | `GET/PATCH /profile`, `/profile/configuration`, `/profile/preferences`, `/profile/options`, `/profile/prompts` | Server-owned onboarding adapter; field mapping | No |
| `POST/PATCH/DELETE /photos`, `/profile_video` | Active Storage multipart, position/primary, media URLs | Profile photos routes; no profile-video route | Photo path adapter; build Profile Video capability | Processing jobs |
| `GET/PUT/DELETE /profile/location`, place/search calls | Coordinates/city and broad location behavior | `/profile/location`, `/profile/place`, `/places`, `/locations/search` | Map private location/place contract | No |
| `GET /search`, `/daily_picks`, `/online_now` | Filtered user cards, limits, activity | `/find`, `/discovery`, profile routes | Discovery response/filter/limit adapter; preserve semantics via Date9ja policy | No |
| `GET /profiles/:id` | User ID profile detail and side effects | `GET /profiles/:profile_id` | Map IDs and explicit view recording | Possibly notifications |
| `POST /profiles/:id/like`, `/super_like`, `POST/DELETE /likes` | User target, like kind, idempotent response | `POST /profiles/:profile_id/likes`, incoming/outgoing likes | Map target IDs and response shape | Notification |
| `POST/DELETE /profiles/:id/pass`, rewind | Pass/unpass/rewind action | `POST /profiles/:profile_id/pass`; no complete rewind route | Build/enable equivalent Match policy | No |
| `GET /likes`, `/received_likes` | Incoming/outgoing lists | `/likes/incoming`, `/likes/outgoing` | List serializer adapter | Notification |
| `GET /matches`, `POST /matches/:id/unmatch` | Match user IDs and match detail | `GET /matches`, `POST /matches/:match_id/unmatch` | Map match public IDs | No |
| `POST /profiles/:id/block`, `GET/DELETE /blocks` | User block target/list | Profile block create/list/delete routes | Map profile IDs and cleanup semantics | No |
| `POST /profiles/:id/report`, `POST /reports`, `/messages/:id/report` | Category/body, user/message target | `/profiles/:profile_id/report`, `/reports` | Map target types/error codes and evidence | Admin only |
| `GET/POST /matches/:id/messages` | Match-scoped messages, pagination, media kinds | `/conversations/:conversation_id/messages` | Match→conversation resolver/adapter | Action Cable redesign |
| `PATCH /matches/:id/messages/read` | Marks messages read for current user | No same path; participant read state in conversation API | Map to participant `last_read_at` contract | Unread badge |
| `PATCH/DELETE /messages/:id`, `POST /messages/:id/reactions` | Edit/delete/reaction by message ID | Message edit/delete paths; no reaction path | Build reactions; map opaque message IDs | Realtime |
| `POST /matches/:id/messages` media | Multipart attachment plus kind/duration/reply | Conversation message/attachment upload paths | Build media-message adapter and processing states | Realtime |
| `GET /notifications`, `PATCH /notifications/:id/read`, read-all | Kind/payload/read state | `/notifications`, `/notifications/:id/read`, `/notifications/read_all` | Map payload/type/read response | Notification Cable |
| `PATCH /notification_preferences`, `/email_notification_preferences` | JSON preference maps | `/notifications/preferences` GET/PATCH | Map known categories and preserve opt-outs | No |
| `POST/DELETE /push_tokens` | Raw token/platform/device | `POST /device_registrations` equivalent must be exposed | Mobile adapter; encrypt/digest token | Push provider |
| `GET /profile_views` | Viewer/target history | No equivalent | Build Engagement/Profile Views capability | Notification |
| `GET/POST/DELETE /dating_hub/batches`, contacts, notes | CRUD batches/contacts/notes/suggestions | No equivalent | Build shared Engagement/Dating Hub primitives | Maybe reminders |
| `GET/PATCH /dating_hub/persona`, `/daily_life` | Persona and daily-life JSON | No equivalent | Build shared AI/Engagement capability | Reminder jobs |
| `GET/POST /aunty_phobie`, messages | AI conversation, client message ID | No equivalent | Build shared AI assistant with Date9ja policy | Streaming/notifications |
| `/community/questions`, answers/votes/reports | Browse/create/answer/vote/report | No equivalent | Build shared Community API and serializers | Moderation/notifications |
| `/community/events`, RSVP/remarks/attendees | Event CRUD, RSVP, remarks | No equivalent | Build shared Community API | Notifications |
| `/community/stories`, remarks | Story CRUD/remarks | No equivalent | Build shared Community API | Notifications |
| `GET /trust_score`, `/verification/*` | Trust score/tier/status | No equivalent full target | Build shared Trust/Verification API | Admin/provider |
| `/admin/*` moderation and operational endpoints | Admin JWT, broad user IDs | D8N brand-scoped Admin/HQ paths | Separate admin adapter; require explicit brand authorization | Admin audit |

## Web versus mobile

Web and mobile call the same identity, profile, dating, messaging, notification, verification, Community, Dating Hub, Aunty Phobie, and admin families. The web client uses `localStorage` and browser multipart `File`; the mobile client uses Expo SecureStore, URI multipart bodies, push registration, and mobile notification listeners. Mobile has an explicit unauthorized listener and therefore needs a session-transition event that preserves the account while replacing the token. Both clients need the same missing shared capabilities; mobile additionally needs native push/deep-link/realtime acceptance tests.

## Machine-checkable follow-up

Before implementation, convert this manifest into a versioned JSON/YAML fixture consumed by web and mobile contract tests. Each row should include `legacy_path`, `method`, `client_set`, `d8n_path`, `status`, `request_fixture`, `response_fixture`, and `realtime_contract`. CI should fail if a client calls an endpoint absent from the Date9ja D8N contract.
