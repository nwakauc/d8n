# DateZA Compatibility v1 Contract

**Status:** Implemented  
**Strategy version:** `dateza_v1`  
**Current API surface:** DateZA profiles returned by `GET /api/v1/find`

Compatibility answers how well one eligible DateZA pair fits based on typed
information both members chose to provide. It is symmetric, deterministic and
calculated per pair. It is not stored on a profile and does not use popularity,
likes, matches, Trust, risk, moderation, RealMe, verification, activity, or exact
location.

## Eligibility boundary

Standalone compatibility calls first apply shared DateZA eligibility: same
brand, active/published membership and profile, no bilateral block, reciprocal
gender interest, reciprocal age range, and reciprocal distance range. An
ineligible or cross-brand pair fails neutrally and receives no compatibility.
Find passes its already-eligible candidates directly to the same calculator.

Compatibility does not add exclusions. DateZA does not yet have typed explicit
partner dealbreakers, so relationship, family and smoking conflicts lower the
score rather than silently hiding a profile.

## Versioned weights

Scores normalize only across dimensions meaningfully present for both members:

| Dimension | Weight |
| --- | ---: |
| Relationship intention | 20 |
| Has children | 10 |
| Wants children | 20 |
| Smoking | 10 |
| Drinking | 5 |
| Faith importance | 8 |
| Social style | 7 |
| Meeting pace | 7 |
| Interests | 4 |
| Languages | 3 |
| Communication style | 2 |
| Planning style | 2 |
| Travel frequency | 1 |
| Diet | 1 |

Total possible comparable weight is 100. Single-choice dimensions use frozen
`dateza_v1` symmetric fit matrices: exact agreement scores 1.0; compatible
adjacent/flexible answers receive partial credit; explicit relationship/family
conflicts score 0.0–0.4. Children status mismatch is 0.5 and is not an inferred
dealbreaker. Interests use Jaccard overlap. Languages use overlap coefficient so
a shared usable language is recognized without rewarding long lists. The small
supporting dimensions cannot dominate relationship/family disagreement.

`prefer_not_to_say`, blank values, or a dimension missing on either side are not
comparable and add neither earned points nor available weight.

## Confidence and publication

`confidence` is comparable weight divided by 100, rounded to two decimals:

- `low`: below 0.45
- `medium`: 0.45–0.74
- `high`: 0.75–1.0

A public score requires at least 35 comparable weight. Below that threshold the
Find `compatibility` property is null—never a fabricated low score or reasons.
When published, score is the rounded normalized earned percentage from 0–100.
The same pair and inputs always reproduce the same result under `dateza_v1`.

## Response

```json
{
  "score": 87,
  "confidence": 0.82,
  "confidence_level": "high",
  "version": "dateza_v1",
  "reasons": [
    "shared_long_term_intent",
    "compatible_family_plans",
    "similar_social_style"
  ]
}
```

At most five reasons are returned, in stable dimension-priority order. Allowed
codes are:

- `shared_long_term_intent`, `compatible_relationship_goals`,
  `relationship_goal_mismatch`
- `compatible_family_plans`, `family_plan_mismatch`
- `shared_no_smoking`, `smoking_lifestyle_mismatch`,
  `compatible_drinking_style`
- `similar_faith_importance`, `similar_social_style`,
  `compatible_meeting_pace`
- `shared_interests`, `shared_languages`
- `compatible_communication_style`, `compatible_planning_style`,
  `similar_travel_style`, `compatible_diet`

Codes intentionally reveal no raw owner-only response, exact faith/religion,
exact location, Trust/risk signal, or inferred sensitive trait. Clients own
localized copy and must not reinterpret compatibility as safety or quality.

## Find and Discovery

Find computes compatibility only after its transaction has allocated the page;
calculation creates no exposure and does not change the daily-10 allowance,
filter, ordering, or cursor. DateZA's configured `discovery.curated_daily`
surface calls this same strategy to rank a bounded eligible pool when it creates
the persisted daily batch. Its compatibility payload is stored with each ordered
allocation member so repeated delivery does not rerank the batch.

Deferred: explicit partner dealbreakers, AI explanations or
Matchmaker, RealMe, public Trust standing, subscriptions, and frontend UI.
