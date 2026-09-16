-- Manual, reviewed one-off fix for the 2-user promotion (retry: previous
-- attempt failed on an untyped NULL literal, safely rolled back). Every
-- value below is now explicitly cast to its column's real type.
--
-- Production's brand_memberships already had id=945 taken (the founder's
-- own admin Date9ja membership, created by bootstrap_founder, which the
-- disposable source DB never knew about) -- so these 2 new rows must get
-- fresh, auto-generated ids instead of the source's original 945/946, and
-- the corresponding profiles rows (production profiles max is 944, so
-- their own ids 945/946 are safe to preserve as-is) must have
-- brand_membership_id explicitly remapped to match. Step 1 (users/
-- identity_identifiers/credentials/credential_password_hashes) already
-- ran and committed successfully.
BEGIN;

CREATE TEMP TABLE new_membership_ids AS
WITH inserted AS (
  INSERT INTO brand_memberships (brand_id, created_at, deleted_at, status, updated_at, user_id)
  VALUES
    (2, '2026-09-16 02:55:48.162226', NULL, 0, '2026-09-16 02:55:48.162226', 950),
    (2, '2026-09-16 02:55:48.301490', NULL, 0, '2026-09-16 02:55:48.301490', 951)
  RETURNING id, user_id
)
SELECT * FROM inserted;

\echo New brand_membership ids:
SELECT * FROM new_membership_ids ORDER BY user_id;

INSERT INTO profiles (
  id, bio, birthdate, body_type, brand_id, brand_membership_id, children_count, city,
  company_name, country_code, created_at, deleted_at, display_name, drinking, fitness,
  gender, height_cm, job_title, languages, languages_spoken, looking_for_text, metadata,
  occupation, pronouns, public_id, school_or_institution, smoking, status, updated_at,
  user_id, visibility, is_nigerian, state_of_origin, nationality, ideal_partner_description,
  willing_to_relocate, relocation_preferences, interest_in_nigerian_culture,
  faith_family_expectations
)
SELECT
  945::bigint,
  $b$Pretty chilled guy. I like people who don't take themselves too seriously but know when to be serious. I'm always down for good food, random drives, deep conversations at 2 a.m., trying something new, or just staying in and doing absolutely nothing together.

I appreciate people who are kind, can communicate, and know how to laugh. Life is already stressful enough, so I'd rather build something that feels easy, peaceful, and fun.

Not really into endless talking stages or playing games. If we vibe, let's see where it goes. If not, no hard feelings.

Bonus points if you can match my sarcasm, send me random memes, or convince me to leave the house when I've been indoors for too long.$b$::text,
  '1990-12-10'::date,
  'muscular'::character varying(32),
  2::bigint,
  (SELECT id FROM new_membership_ids WHERE user_id = 950)::bigint,
  NULL::integer,
  NULL::character varying(120),
  NULL::character varying(120),
  'ZA'::character varying(2),
  '2026-09-16 02:55:48.198641'::timestamp,
  NULL::timestamp,
  'Uche'::character varying(80),
  'occasionally'::character varying(32),
  'never'::character varying(32),
  'man'::character varying(32),
  187::integer,
  NULL::character varying(120),
  '[{"code": "ig"}, {"code": "en"}]'::jsonb,
  '[]'::jsonb,
  $b$I'd love to meet someone who's ready for something real. Kind, honest, family-oriented, emotionally available, and open to building a future together. Someone who values respect, loyalty, and teamwork because the best relationships aren't perfect they're built by two people who keep choosing each other.$b$::text,
  '{"date9ja_legacy_arrays": {"interests": ["Football", "Mountain climbing"], "dealbreakers": ["smoking", "yahoo yahoo"], "languages_spoken": ["Igbo", "English"], "relationship_values": ["communication", "friendship", "companinonship"]}}'::jsonb,
  'Engineer'::character varying(120),
  NULL::character varying(40),
  '8e79c697-23d2-4b80-9acc-968afb37b3df'::uuid,
  NULL::character varying(160),
  'never'::character varying(32),
  1::integer,
  '2026-09-16 02:58:05.174701'::timestamp,
  950::bigint,
  1::integer,
  true::boolean,
  'Imo'::character varying(80),
  NULL::character varying(2),
  NULL::text,
  true::boolean,
  '{Europe,Canada,Australia}'::character varying[],
  NULL::text,
  NULL::text
UNION ALL
SELECT
  946::bigint,
  NULL::text,
  '1990-07-23'::date,
  NULL::character varying(32),
  2::bigint,
  (SELECT id FROM new_membership_ids WHERE user_id = 951)::bigint,
  NULL::integer,
  NULL::character varying(120),
  NULL::character varying(120),
  'ZA'::character varying(2),
  '2026-09-16 02:55:48.309707'::timestamp,
  NULL::timestamp,
  'Dev'::character varying(80),
  NULL::character varying(32),
  NULL::character varying(32),
  'woman'::character varying(32),
  NULL::integer,
  NULL::character varying(120),
  '[]'::jsonb,
  '[]'::jsonb,
  NULL::text,
  '{}'::jsonb,
  NULL::character varying(120),
  NULL::character varying(40),
  '00b8dcfb-990a-4b29-a653-4a454e8783d5'::uuid,
  NULL::character varying(160),
  NULL::character varying(32),
  1::integer,
  '2026-09-16 02:58:05.456427'::timestamp,
  951::bigint,
  1::integer,
  NULL::boolean,
  NULL::character varying(80),
  NULL::character varying(2),
  NULL::text,
  NULL::boolean,
  '{}'::character varying[],
  NULL::text,
  NULL::text;

\echo Profiles inserted:
SELECT id, user_id, brand_membership_id, display_name FROM profiles WHERE user_id IN (950, 951) ORDER BY user_id;

COMMIT;
