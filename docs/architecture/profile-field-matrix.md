# Profile Field Matrix

## Purpose

This matrix is design evidence for ADR 0008. It maps active HookUs and Date9ja profile behavior into D8N ownership boundaries before migrations are written.

The inventory was taken from the reference applications on 2026-08-13, primarily:

- `hookus/api/app/models/user.rb`
- `hookus/api/app/controllers/api/v1/me_controller.rb`
- `hookus/api/app/serializers/user_serializer.rb`
- `hookus/api/app/serializers/profile_card_serializer.rb`
- `hookus/api/app/services/users/profile_completion_service.rb`
- `hookus/api/app/services/matching/compatibility_score_service.rb`
- `Date9ja/api/app/models/user.rb`
- `Date9ja/api/app/controllers/api/v1/me_controller.rb`
- `Date9ja/api/app/serializers/user_serializer.rb`
- `Date9ja/api/app/serializers/profile_card_serializer.rb`
- `Date9ja/api/app/services/users/profile_completion_service.rb`
- `Date9ja/api/app/services/matching/compatibility_score_service.rb`
- The HookUs web API types and Date9ja web/mobile onboarding and profile editors

Reference repositories are behavioral evidence, not D8N architecture templates. A field appearing in a legacy `users` table does not mean it belongs on D8N `User`.

## Classification Key

- **Core profile**: stable brand-owned dating presence.
- **Preference**: brand-owned discovery or partner preference.
- **Controlled option**: stable field/group key with managed option codes.
- **Questionnaire**: version-aware compatibility question and answer.
- **Dedicated domain**: not profile data despite appearing in a legacy profile response.
- **Decision required**: product or migration semantics are not sufficiently settled.

## Shared Profile Capabilities

| Legacy field | Cardinality | HookUs use | Date9ja use | Visibility/behavior | Proposed D8N ownership |
|---|---|---|---|---|---|
| `full_name` | Scalar text | Registration/private account | Registration/private account | Never on public card | Platform Identity: separate private `User.first_name` and `User.last_name`; self-declared until independently verified |
| `display_name` / legacy public `first_name` | Scalar text | Completion and public card | Completion and public card | Public | Core profile: independent `Profile.display_name`; never derive or expose the private surname |
| `date_of_birth` | Date | Required; age matching | Required; age matching | Private source; expose derived age | Core profile with strict privacy and age derivation |
| `gender` | Single select | Required; discovery orientation | Required; discovery orientation | Public | Named profile capability with brand-configured allowed values |
| `looking_for` | Single or multi select | Required; reciprocal discovery | Required; reciprocal discovery | Private preference, affects discovery | Preference capability; D8N must support future multi-select semantics |
| `country_of_residence` | Single country | Required, normalized | Required, normalized | Public at country granularity; matching/filtering | Core profile location capability using canonical country codes |
| `city` | Scalar/location label | Optional public location | Optional public location | Public; discovery display | Core profile location capability |
| `location_latitude`, `location_longitude` | Coordinate pair | Distance filtering/scoring | Distance filtering | Private; never serialize to other members | Private profile location record, not metadata |
| `occupation` | Scalar text | Optional public enrichment | Optional public enrichment | Public | Core profile detail, bounded text |
| `about_me` | Scalar text | Required completion | Required completion | Public; bounded | Core profile `bio` |
| `height` | Integer | Optional public enrichment | Optional public enrichment | Public; may later filter | Shared typed profile detail |
| `body_type` | Scalar text with suggestions | Optional public enrichment | Optional public enrichment | Public | Bounded profile text; do not force taxonomy without product approval |
| `languages_spoken` | Multi-value | Optional enrichment | Optional enrichment | Public | Controlled or canonicalized multi-value profile capability |
| `smoking` | Single select | Optional enrichment | Optional enrichment | Public; potentially matching | Named lifestyle capability with controlled options |
| `drinking` | Single select | Optional enrichment | Optional enrichment | Public; potentially matching | Named lifestyle capability with controlled options |
| `fitness` | Single select | Optional enrichment | Optional enrichment | Public; potentially matching | Named lifestyle capability with controlled options |
| `preferred_age_min` | Integer | Optional filtering/scoring | Optional filtering/scoring | Private preference | Typed preference with ordered-range validation |
| `preferred_age_max` | Integer | Optional filtering/scoring | Optional filtering/scoring | Private preference | Typed preference with ordered-range validation |
| `preferred_distance_km` | Integer | Optional reciprocal distance filter | Optional reciprocal distance filter | Private preference | Typed preference; requires coordinates |
| `profile_hidden` | Boolean | Discovery exclusion | Discovery exclusion | Private setting | Profile visibility/status capability |
| `hide_last_seen` | Boolean | Controls derived online status | Controls derived online status | Private setting; affects public derivation | Presence privacy setting, not profile taxonomy |
| `photos` | Ordered collection | Required completion | Required completion | Public after policy/moderation | Brand-owned Media/ProfilePhoto collection |
| `profile_video` | Optional media | Public presence indicator/detail | Public presence indicator/detail | Moderated media | Brand-owned Media capability |

## HookUs-Specific Evidence

| Field/concept | Cardinality | Requiredness | Active behavior | Proposed D8N ownership |
|---|---|---|---|---|
| `intents` | Multi-select, max 15 in reference | Required by onboarding gate | Public, search filter, 40% compatibility dimension | Controlled profile option group; brand-managed codes and explicit max selections |
| `vibes` | Multi-select, max 15 in reference | Required for D8N HookUs onboarding | Public, search filter, 25% compatibility dimension | Controlled profile option group with brand-managed codes and explicit max selections |
| `hook_tonight_active` | Derived boolean | Not profile completion | Discovery space and public derived state | Dedicated ephemeral Availability record with activity and expiry |
| `hooks_remaining`, `hooks_reset_at` | Counter and timestamp | Not profile completion | Limits stronger-than-like interaction | Matching/Entitlement capability, not Profile |
| `rewind_used_on` | Date/counter state | Not profile completion | Interaction allowance | Matching/Entitlement capability, not Profile |

HookUs completion currently has two non-identical legacy definitions: `User#onboarding_complete?` does not require vibes, while `ProfileCompletionService` reports them. The founder confirmed on 2026-08-13 that vibes are required in D8N. D8N must use one authoritative gate and derive progress from the same rule set.

## Date9ja Cultural And Relationship Capabilities

| Field | Cardinality | Requiredness | Active behavior | Proposed D8N ownership |
|---|---|---|---|---|
| `is_nigerian` | Boolean | Required branch selector | Selects cultural completion path | Typed profile cultural capability |
| `state_of_origin` | Single region | Required when Nigerian | Public and cultural identity | Canonical region profile capability scoped by country |
| `tribe` | Scalar text/suggested option | Required when Nigerian | Public, discovery preference and 20% compatibility dimension | Bounded normalized cultural profile value; option strategy requires migration review |
| `nationality` | Single country/nationality | Required when not Nigerian | Public cultural identity | Canonical profile capability |
| `ethnicity` | Single select | Optional | Public enrichment | Named profile capability with controlled options |
| `religion` | Single select | Required | Public, filtering and 30% compatibility dimension | Named semantic profile capability with brand-configured controlled options |
| `denomination` | Scalar text/suggested option | Optional | Public enrichment | Bounded profile value; do not assume every religion uses it |
| `education` | Single select | Optional | Public enrichment | Named profile capability with controlled options |
| `marital_status` | Single select | Optional | Public enrichment | Named profile capability with controlled options |
| `relationship_intention` | Single select | Required | Public and 10% compatibility dimension | Named semantic profile capability; allowed values differ by brand |
| `commitment_timeline` | Single ordered select | Required | Public and ordered 5% compatibility dimension | Named profile capability with controlled, ordered options |
| `willing_to_relocate` | Boolean | Required branch selector | Matching and completion | Typed profile/preference capability |
| `relocation_preferences` | Multi-value, max 5 in reference | Required when willing to relocate | Compatibility and discovery | Canonicalized multi-value preference with explicit maximum |
| `wants_children` | Single select | Required | Public and 5% compatibility dimension | Named semantic profile capability with controlled options |
| `children_count` | Single select | Optional | Public enrichment | Named profile capability with controlled options |
| `polygamy_openness` | Single select | Optional | Public enrichment | Named relationship capability with controlled options |
| `intertribal_marriage_openness` | Boolean | Optional | Changes tribe compatibility result | Typed relationship capability |
| `family_involvement_preference` | Single ordered select | Optional | Public enrichment | Named relationship capability with controlled options |
| `interest_in_nigerian_culture` | Scalar text | Optional | Public for non-Nigerian context | Bounded cultural profile text |
| `interests` | Multi-value | Optional | Public enrichment | Controlled option group only after current values and migration quality are inventoried |

## Date9ja Partner Preferences

| Field | Cardinality | Requiredness | Active behavior | Proposed D8N ownership |
|---|---|---|---|---|
| `preferred_countries` | Multi-value | Optional | Reciprocal discovery filter | Canonical country preference selections |
| `preferred_religion` | Multi-value | Optional | Reciprocal discovery filter | Controlled preference selections tied to religion option codes |
| `preferred_tribes` | Multi-value text | Optional | Reciprocal case-insensitive discovery filter | Normalized preference values; migration quality must be measured |
| `ideal_partner_description` | Scalar text | Optional | Public profile detail | Bounded preference/profile text, explicit public visibility |
| `relationship_values` | Multi-value | Optional | Public profile detail | Controlled option group if retained by product |
| `dealbreakers` | Multi-value/free text | Optional | Public profile detail; not currently a hard filter | Product decision required: bounded text statements or controlled options |

## Date9ja Compatibility Questionnaire

The Date9ja `v2_onboarding_answers` JSON currently accepts these keys:

| Answer key | Used by matching now | Proposed D8N treatment |
|---|---|---|
| `faith_practice` | Yes, ordered score | Versioned controlled questionnaire answer |
| `language_at_home` | Yes, compatibility score | Versioned controlled questionnaire answer |
| `money_providing` | Yes, compatibility score | Versioned controlled questionnaire answer |
| `conflict` | Yes, ordered score | Versioned controlled questionnaire answer |
| `family_involvement` | No direct score; mapped to profile field | Preserve migration source; avoid duplicate source of truth |
| `settlement` | No direct score; mapped to relocation fields | Preserve migration source only if needed for audit |
| `children` | No direct score; mapped to wants-children | Preserve migration source only if needed for audit |
| `lifestyle` | No direct score | Product decision required before migration |
| `genotype` | No current score | Sensitive-data and product review required before collection |
| `custom_religion` | No direct score | Bounded conditional text if retained; privacy review required |

Questionnaire definitions need stable question and option codes, a questionnaire version, brand ownership, retirement behavior, and explicit matching consumers. They must not become an unrestricted JSON extension point.

## Fields Outside This ADR

These values appear in legacy `UserSerializer` responses or `users` tables but belong to other D8N domains:

| Legacy fields/concepts | D8N domain |
|---|---|
| `email`, `phone`, password/JWT/confirmation fields | Identity/Credentials |
| `verification_tier`, `phone_verified_at`, `realme` | Verification |
| `trust_xp`, `trust_score`, moderation flags | Trust and Moderation |
| `subscription_status`, `premium_expires_at`, `founding_member` | Billing/Entitlements |
| `last_active_at`, `online_now` | Presence |
| `hooks_remaining`, `rewind_used_on` | Matching/Entitlements |
| `notification_preferences`, unread counts | Notifications/Messaging |
| `admin`, suspension and ban state | Admin/Trust/Identity policy |
| acquisition and device fields | Analytics/Security |
| `aunty_phobie_language` | Separate assistant/product capability; not profile taxonomy |

## Conditional Completion Proof Cases

The completion design is not accepted until one brand can evaluate all applicable rules in the same request. At minimum, tests must cover:

| Case | Expected missing requirements |
|---|---|
| Nigerian, not relocating | `state_of_origin`, `tribe`; no `nationality` or relocation destinations |
| Nigerian, relocating | `state_of_origin`, `tribe`, `relocation_preferences` |
| Non-Nigerian, not relocating | `nationality`; no Nigerian origin fields or relocation destinations |
| Non-Nigerian, relocating | `nationality`, `relocation_preferences` |
| Branch selector unanswered | Selector itself, without guessing a branch |

Simple base requirements such as display name, birthdate, gender, relationship intention, bio, and photos must be evaluated alongside these branches.

## Decisions Required Before Implementation

1. Confirm Date9ja's authoritative required fields against current product intent, not only legacy behavior.
2. Inventory Date9ja production value counts, null rates, and invalid values before final migration mappings.
3. Define future verified-name claim provenance, comparison, review, and history semantics; typed private names now belong to platform Identity.
4. Approve the controlled-option boundary for tribe, body type, interests, values, and dealbreakers.
5. Decide whether compatibility questionnaire history must be retained across answer changes.
6. Complete privacy review for genotype, religion, ethnicity, precise location, and other sensitive attributes.

Confirmed founder decisions on 2026-08-13:

- HookUs vibes are required for onboarding.
- Date9ja is live and has existing users; it must be treated as a production data migration.

## Approval Gate

ADR 0008 is accepted for the initial HookUs capability implementation. The unresolved decisions above remain a gate for Date9ja production migration mappings, not for additive HookUs development.
