# Feature Parity Acceptance Criteria

**Gate:** Full retained Date9ja feature parity is a production cutover requirement. Data migration success alone is insufficient. No active production capability may be replaced with “Coming soon”.

## Identity and profile journeys

- Existing user signs in with the existing password, receives a D8N Date9ja session, and lands in the existing Date9ja experience without forced onboarding.
- Existing confirmed/unconfirmed email and phone states behave according to the approved legacy policy.
- Existing user resets a password, logs out, recovers/reactivates where supported, and deletes/deactivates without cross-brand effects.
- Existing profile opens with the same public fields, private-field protections, completion state, visibility, and moderation state.
- Existing user edits each retained profile field and preference; values survive reload and remain discoverable according to the same policy.
- Existing photos appear in the same order with the same primary photo and moderation/publication state; user can upload, reorder, replace, and delete.
- Existing profile video remains viewable, editable, deletable, and correctly moderated.
- Existing location, age range, interested-in, relationship intent, culture/faith/family, relocation, interests, prompts, and about fields retain approved semantics.

## Discovery and relationships

- User A discovers User B under the same filters, location rules, limits, ordering policy, and activity signals.
- Opening B records one profile view with correct viewer/target and does not double-count on refresh.
- A passes, unpasses/rewinds where currently supported, likes, and super-likes B; direction, timestamps, limits, and notifications are correct.
- B receives the incoming-like notification, likes A, and one match is created with correct participants.
- Existing matches remain visible, unmatch works, and blocked users remain excluded in both directions.
- Existing profile and message reports retain categories, notes, open/resolved state, evidence, and moderation visibility.

## Messaging and realtime

- Existing conversation opens with all messages in stable chronological order, including deleted/edited/reply/media state.
- A sends text, image, voice, and video messages where source supported; B receives them with correct media access and metadata.
- B receives a realtime message, unread count/toast/sound behavior matches the existing product, and marking read affects only B.
- Message edit/delete, reply, report, and emoji reaction create/delete work with the same user-visible semantics.
- Reconnect, duplicate client requests, pagination, and Action Cable authorization do not duplicate or expose messages.

## Verification, trust, notifications, and moderation

- Existing selfie/video/government-ID/RealMe status, badge, review state, and permitted evidence access are preserved or explicitly approved for a shared D8N implementation.
- Trust XP/score, reputation badges, moderation flags, sanctions, and publication state remain correct.
- In-app, email, SMS, and push notifications retain supported preferences and do not replay historical deliveries.
- Device registration, token rotation/revocation, notification read state, realtime notification badges, and deep links work on web and mobile.

## Community, Dating Hub, Aunty Phobie, and monetization

- User can perform every currently exposed Community browse/create/answer/vote/report/RSVP/story/remark operation; moderation and notifications work.
- User can perform every exposed Dating Hub batch/contact/note/suggestion/coach/persona/daily-life operation; matched and external contacts remain distinct.
- Aunty Phobie retains conversation history, language/personality, usage limits, provider failure behavior, escalation, and privacy controls.
- Premium/founding users retain entitlement, limits, and access; free users do not gain or lose access unintentionally.

## Automated gates

Run these journeys on a production-shaped staging snapshot for web and mobile, with source/destination row IDs linked by the migration map. Require zero unexplained failures, orphaned records, duplicate relationships, missing media, or behavior changes. Any intentional semantic change requires product approval recorded with the test result.
