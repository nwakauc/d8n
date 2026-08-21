# DateZA v1 Profile and Onboarding Contract

**Status:** Implemented on D8N as of 2026-08-21  
**Brand:** DateZA (`dateza`)

DateZA clients must obtain this contract from authenticated
`GET /api/v1/profile/configuration`. D8N owns requiredness, completion,
publication eligibility, and `onboarding.next_step`; web and mobile clients must
not duplicate those rules.

## Required to publish

- Profile fields: `display_name`, `birthdate`, `gender`, `country_code`, `city`,
  `bio`, `smoking`, and `drinking`.
- Partner preferences: `interested_in`, `min_age`, `max_age`, and
  `max_distance_km`.
- Collections: at least one profile photo.
- Controlled option groups: `relationship_intent`, `has_children`,
  `wants_children`, `religion_importance`, `social_style`, and `meeting_pace`.

`has_children`, `wants_children`, `religion_importance`, and optional `religion`
are owner-only. They are stored as typed option codes for future private
compatibility use and are not returned by the public profile serializer.

## Optional profile expression

- Scalar/structured fields: `occupation`, `job_title`, `height_cm`, `languages`,
  and `fitness`.
- Controlled groups: `education_level`, `religion`, `diet`, `pets`,
  `travel_frequency`, `communication_style`, `planning_style`, and `interests`.
- Prompts: `green_flag`, `ideal_first_meet`, `looking_for`, `weekend_plan`,
  `geek_out`, and `dealbreaker`.

Optional fields never block publication. The language taxonomy includes all 11
official South African languages and remains reusable by other brands.

## Matching semantics (data only)

- Hard eligibility already represented by D8N: reciprocal `interested_in`, the
  member's age range, maximum distance, brand membership, profile publication,
  blocks, and safety/account status.
- Potential future explicit dealbreakers: relationship intention, children or
  future-children preferences, and smoking. This release stores a member's own
  typed answers; DateZA compatibility v1 treats them as high-weight dimensions,
  not inferred hard exclusions.
- Compatibility v1 soft signals: drinking, faith importance, social style,
  meeting pace, diet, interests, languages, communication style, planning style,
  and travel frequency.

The profile contract does not own weights. The separate versioned compatibility
strategy consumes these typed values; DateZA Discovery remains unimplemented.

## Location and privacy

`country_code: "ZA"` plus `city` provides the v1 coarse South African location.
Exact latitude/longitude may be written through the existing private profile
location endpoint but are never returned in public profile JSON. Province is not
stored as a typed profile field in the current schema and has deliberately not
been emulated with free-form metadata.

## Progressive client flow

Clients can group the returned configuration into Basics, Location and dating
range, Relationship essentials, Profile expression, and Review/publish screens.
The authoritative resumable state remains `onboarding`, whose current generic
steps are `profile`, `preferences`, `photos`, `options`, and `publication`.

## Explicitly not implemented

Member-configured hard dealbreakers, RealMe, public Trust standing, daily
Discovery 10, AI Matchmaker, subscriptions,
product notifications, frontend screens, and a province catalogue remain future
work.

DateZA Find and its daily 10-unique-profile exposure allowance are implemented
separately from this onboarding contract; see `GET /api/v1/find` in the canonical
OpenAPI document.
Compatibility v1 is described in [`COMPATIBILITY_V1.md`](COMPATIBILITY_V1.md).
