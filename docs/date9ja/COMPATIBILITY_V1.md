# Date9ja Compatibility v1

`date9ja_v1` is a deterministic, symmetric pair score for Date9ja's
marriage-first product. It has two deliberately separate outputs:

1. a relationship compatibility percentage; and
2. a hemoglobin-genotype critical check.

Genotype is not a weighted score that other strengths can cancel out. It is
shown separately so the frontend can make the information prominent without
calling a member or relationship medically "compatible" or "safe".

## Relationship score

| Dimension | Weight |
| --- | ---: |
| Religion | 30 |
| Tribe / intertribal openness | 20 |
| Country / relocation fit | 20 |
| Relationship intention | 10 |
| Mutual age fit | 10 |
| Commitment timeline | 5 |
| Children plans | 5 |
| Faith practice | 8 |
| Money expectations | 8 |
| Conflict style | 8 |

Only dimensions answered by both members enter the denominator. A percentage
is published only when at least three dimensions and 44 weight points are
comparable. Below that threshold, `score` is `null`; it is never converted to
zero. `confidence` is the comparable weight divided by the full 124 points.

The score is pair-specific and symmetric. It must not include activity,
verification, popularity, payments, likes, Trust state, or exact location.

## Genotype critical check

The check is calculated only from the two reported genotype codes. It does not
infer an answer from ethnicity, family history, geography, or any other field.

| Status | Meaning | Product behavior |
| --- | --- | --- |
| `not_assessed` | Either answer is missing, not tested, or prefer-not-to-say | Pass through; do not block or down-rank; prompt gently if appropriate |
| `clinical_review_required` | A present value is outside the supported vocabulary | Pass through and avoid a conclusion |
| `no_elevated_risk_identified` | The supported pair produces no HbSS/HbSC outcome in the simple inheritance calculation | Show the qualified wording; never label "safe" |
| `elevated_sickle_cell_risk` | The supported pair can produce an HbSS or HbSC outcome | Do not include in curated daily introductions; show prominently on other eligible profile surfaces |
| `other_hemoglobin_risk` | The supported pair can produce an HbCC outcome | Do not include in curated daily introductions; show prominently elsewhere and recommend professional review |

Known outcomes include probabilities in the API. For example, reported AS + AS
produces a 0.25 HbSS probability and AS + AC produces a 0.25 HbSC probability
under the simple allele model. These are per-pregnancy inheritance
probabilities, not predictions about a particular child.

## Frontend presentation

Show the percentage and critical check as separate cards. Recommended copy:

- `not_assessed`: **Genotype not assessed** — “One or both of you have not
  shared a tested genotype. This does not affect your compatibility score.”
- `no_elevated_risk_identified`: **No elevated sickle-cell outcome identified**
  — “Based only on both self-reported genotypes.”
- `elevated_sickle_cell_risk`: **Genotype needs attention** — “These reported
  genotypes can carry an inherited sickle-cell-disease outcome. Confirm your
  results and speak with a qualified clinician or genetic counsellor.”
- `other_hemoglobin_risk`: **Genotype needs professional review** — “Confirm
  your results and discuss the combination with a qualified clinician or
  genetic counsellor.”

Do not use “good genotype,” “bad genotype,” “safe to marry,” “incompatible,” or
diagnostic language. Keep the members' reported genotype values visible beside
the explanation so a person can spot a deal-breaker before emotional investment.

## Surfaces and privacy

- Date9ja Explore, Find, daily introductions, profile detail, and like lists
  receive the pair-specific compatibility payload.
- Genotype is an optional Date9ja `public_profile` option and remains disabled
  for other brands.
- Brand, lifecycle, block, and visibility scopes run before scoring.
- Raw genotype must not appear in logs, analytics events, reason codes, or
  cross-brand payloads.
- The UI must label genotype as self-reported and encourage confirmatory testing.

## Migration impact

No database migration is required: the option group and sensitive importer
already exist. The production data migration is affected operationally:

- sanitized rehearsal snapshots intentionally contain no genotype values, so
  they exercise `not_assessed` only;
- the pristine-source census measure 327 must validate the real vocabulary;
- the security/DPIA gate must cover storage, consent notice, and disclosure to
  eligible potential matches before real values are imported; and
- an existing D8N environment must rerun Date9ja brand provisioning after that
  approval so the persisted option-group visibility changes from its former
  owner-only policy to `public_profile`; and
- `SensitiveProfileImport` can then copy recognized values without changing
  the runtime scorer. Unknown values remain quarantined rather than guessed.

## Medical references

- [CDC: inheritance when both parents have sickle cell trait](https://www.cdc.gov/sickle-cell/about/index.html)
- [NHLBI: sickle cell disease causes and inheritance](https://www.nhlbi.nih.gov/health/sickle-cell-disease/causes)
- [WHO: sickle-cell disease fact sheet](https://www.who.int/news-room/fact-sheets/detail/sickle-cell-disease)
