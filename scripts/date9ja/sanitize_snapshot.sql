-- =============================================================================
-- Date9ja migration-rehearsal snapshot sanitizer
-- =============================================================================
-- Authority: docs/migrations/date9ja-to-d8n/SANITIZATION-CONTRACT.md
-- Companion verifier: scripts/date9ja/verify_sanitized_snapshot.sql
--
-- WHAT THIS DOES
--   Deterministically strips secrets, direct identifiers, precise location and
--   private/sensitive UGC from a LOCAL copy of a Date9ja production restore,
--   while preserving the relational graph, legacy IDs and migration-testable
--   state. Fail-closed: aborts (rolls back) rather than partially sanitizing.
--
-- WHAT THIS IS NOT
--   Not a production tool. It never connects to production, never copies media
--   bytes, never uploads anything, never deploys, and never touches the
--   operator's pristine raw restore.
--
-- SAFE LOCAL EXECUTION (operator only — DO NOT run as part of design review):
--   psql -v ON_ERROR_STOP=1 -v sanitize_ack=SANITIZE_THE_COPY \
--        -d date9ja_snapshot_sanitized \
--        -f scripts/date9ja/sanitize_snapshot.sql
--   then:
--   psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
--        -f scripts/date9ja/verify_sanitized_snapshot.sql
--
--   Target MUST be `date9ja_snapshot_sanitized` (a copy).
--   NEVER run against `date9ja_snapshot_tmp` (the pristine raw restore).
-- =============================================================================

\set ON_ERROR_STOP on

-- Require the explicit acknowledgement variable.
\if :{?sanitize_ack}
\else
  \echo '*** ERROR: pass  -v sanitize_ack=SANITIZE_THE_COPY  (see file header) ***'
  \quit
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Operator + environment guards (fail-closed)
-- -----------------------------------------------------------------------------
-- 0a. Acknowledgement token must match exactly (client-side check).
SELECT :'sanitize_ack' = 'SANITIZE_THE_COPY' AS ack_ok \gset
\if :ack_ok
\else
  \echo '*** ERROR: sanitize_ack must equal SANITIZE_THE_COPY ***'
  \quit
\endif

-- 0b. Never run against the named pristine raw restore; refuse a second run.
DO $guard$
DECLARE
  n bigint;
BEGIN
  IF current_database() = 'date9ja_snapshot_tmp' THEN
    RAISE EXCEPTION
      'REFUSING TO RUN: current_database() is date9ja_snapshot_tmp (the pristine raw restore). Target date9ja_snapshot_sanitized only.';
  END IF;

  -- Idempotency guard: several transformations (hashed buckets) are not
  -- safe to apply twice. Start from a fresh copy of the raw restore.
  SELECT count(*) INTO n FROM users WHERE email ~ '@snapshot\.invalid$';
  IF n > 0 THEN
    RAISE EXCEPTION
      'REFUSING TO RUN: % users already have @snapshot.invalid emails — this database looks already sanitized. Start from a fresh copy.', n;
  END IF;
END
$guard$;

-- Audit rows live OUTSIDE public so the public schema stays exactly 51 tables
-- for the shared v2 schema-signature check (schema_signature.sql). The operator
-- drops this schema before packaging the snapshot (see SNAPSHOT-RUNBOOK.md).
DROP SCHEMA IF EXISTS sanitize_audit CASCADE;
CREATE SCHEMA sanitize_audit;

-- -----------------------------------------------------------------------------
-- 1. Schema-drift guard — canonical Date9ja source-schema signature (v2).
--    ONE definition, shared with verify_sanitized_snapshot.sql and
--    source_census.sql. Exact base-table set AND full structural signature
--    (type, nullability, ordinal, precision, default), or abort. Any drift
--    forces SANITIZATION-CONTRACT.md §3 to be revisited before this can run.
-- -----------------------------------------------------------------------------
\ir schema_signature.sql

-- -----------------------------------------------------------------------------
-- 2. Pre-count audit (durable table; the verifier reads it)
-- -----------------------------------------------------------------------------
CREATE TABLE sanitize_audit.counts (
  metric text PRIMARY KEY,
  value  bigint NOT NULL
);
INSERT INTO sanitize_audit.counts (metric, value)
  SELECT 'run_at_epoch', extract(epoch FROM now())::bigint;

INSERT INTO sanitize_audit.counts (metric, value) VALUES
  ('users',                        (SELECT count(*) FROM users)),
  ('photos',                       (SELECT count(*) FROM photos)),
  ('profile_videos',               (SELECT count(*) FROM profile_videos)),
  ('active_storage_blobs',         (SELECT count(*) FROM active_storage_blobs)),
  ('active_storage_attachments',   (SELECT count(*) FROM active_storage_attachments)),
  ('likes',                        (SELECT count(*) FROM likes)),
  ('matches',                      (SELECT count(*) FROM matches)),
  ('messages',                     (SELECT count(*) FROM messages)),
  ('profile_views',                (SELECT count(*) FROM profile_views)),
  ('blocks',                       (SELECT count(*) FROM blocks)),
  ('reports',                      (SELECT count(*) FROM reports)),
  ('profile_passes',               (SELECT count(*) FROM profile_passes)),
  ('message_reactions',            (SELECT count(*) FROM message_reactions)),
  ('verification_checks',          (SELECT count(*) FROM verification_checks)),
  ('trust_events',                 (SELECT count(*) FROM trust_events)),
  ('notifications',                (SELECT count(*) FROM notifications));

-- salt used for every pseudonymous derivation (documented; not a secret)
\set salt 'date9ja-snapshot-v1'

-- =============================================================================
-- 3. TRANSFORMATIONS
--    Only non-key, non-FK columns are rewritten. Every derivation keys on an
--    immutable id, never on row order.
-- =============================================================================

-- 3.1 users ------------------------------------------------------------------
UPDATE users SET
  email                 = 'date9ja+' || id || '@snapshot.invalid',
  unconfirmed_email     = NULL,
  encrypted_password    = '$2a$12$3Jgn6erKwDc0ADnT4arvEOi.EuOE00NCLVpYHtmVAs39f9I2WJbbm',
  full_name             = 'Snapshot User ' || id,
  display_name          = 'Snapshot ' || id,
  phone                 = CASE WHEN phone IS NULL THEN NULL ELSE '+99900000' || id END,
  public_id             = 'usr_' || lpad(to_hex(id), 6, '0')
                          || substr(md5(id::text || :'salt'), 1, 18),
  jti                   = 'snapshot-' || id,
  reset_password_token  = NULL,
  reset_password_sent_at = NULL,
  confirmation_token    = NULL,
  confirmation_sent_at  = NULL,
  current_sign_in_ip    = NULL,
  last_sign_in_ip       = NULL,
  date_of_birth         = CASE WHEN date_of_birth IS NULL THEN NULL
                               ELSE make_date(extract(year FROM date_of_birth)::int, 7, 1) END,
  city                  = NULL,
  -- Coordinates are dropped, not coarsened: a shareable rehearsal snapshot must
  -- not carry real user geography, and no currently-unblocked migration test
  -- needs them (discovery/distance rehearsal is separately gated and can use
  -- deterministic synthetic coordinates when it lands). Reviewer decision, R6.
  location_latitude     = NULL,
  location_longitude    = NULL,
  -- Notification preference JSON: keep only entries whose value is a JSON
  -- boolean (the app's only legitimate shape — allowlisted keys, on/off
  -- toggles). Anything else that ever reached the column by a non-model write
  -- is dropped. Non-object values collapse to {}.
  notification_preferences = CASE
    WHEN jsonb_typeof(notification_preferences) <> 'object' THEN '{}'::jsonb
    ELSE COALESCE((SELECT jsonb_object_agg(e.key, e.value)
                   FROM jsonb_each(notification_preferences) e
                   WHERE jsonb_typeof(e.value) = 'boolean'), '{}'::jsonb)
  END,
  email_notification_preferences = CASE
    WHEN jsonb_typeof(email_notification_preferences) <> 'object' THEN '{}'::jsonb
    ELSE COALESCE((SELECT jsonb_object_agg(e.key, e.value)
                   FROM jsonb_each(email_notification_preferences) e
                   WHERE jsonb_typeof(e.value) = 'boolean'), '{}'::jsonb)
  END,
  about_me                     = CASE WHEN about_me IS NULL THEN NULL ELSE '[redacted]' END,
  ideal_partner_description    = CASE WHEN ideal_partner_description IS NULL THEN NULL ELSE '[redacted]' END,
  interest_in_nigerian_culture = CASE WHEN interest_in_nigerian_culture IS NULL THEN NULL ELSE '[redacted]' END,
  occupation                   = CASE WHEN occupation IS NULL THEN NULL ELSE '[redacted]' END,
  deletion_reason              = CASE WHEN deletion_reason IS NULL THEN NULL ELSE '[redacted]' END,
  suspension_reason            = CASE WHEN suspension_reason IS NULL THEN NULL ELSE '[redacted]' END,
  ban_reason                   = CASE WHEN ban_reason IS NULL THEN NULL ELSE '[redacted]' END,
  -- Sensitive religious / ethnic / tribal / health-adjacent attributes. The
  -- sensitive-field importer is GATED (DECISIONS.md) and will need its own
  -- product-approved extract, so nothing currently justifies carrying real
  -- values (or even their co-occurrence structure). Drop them. Reviewer
  -- decision R1. This is snapshot data-minimisation, not a migration product
  -- decision — the DECISIONS.md rows are untouched.
  tribe                         = NULL,
  denomination                  = NULL,
  state_of_origin               = NULL,
  nationality                   = NULL,
  religion                      = NULL,
  ethnicity                     = NULL,
  intertribal_marriage_openness = NULL,
  polygamy_openness             = NULL,
  is_nigerian                   = NULL,
  preferred_religion  = '{}'::character varying[],
  preferred_tribes    = '{}'::character varying[],
  interests           = '{}'::character varying[],
  relationship_values = '{}'::character varying[],
  dealbreakers        = '{}'::character varying[],
  v2_onboarding_answers = '{}'::jsonb,
  signup_source        = CASE WHEN signup_source IS NULL THEN NULL
                              ELSE 'bucket_' || (abs(hashtext(lower(signup_source))::bigint) % 16)::text END,
  attribution_source   = CASE WHEN attribution_source IS NULL THEN NULL
                              ELSE 'bucket_' || (abs(hashtext(lower(attribution_source))::bigint) % 16)::text END,
  attribution_medium   = CASE WHEN attribution_medium IS NULL THEN NULL
                              ELSE 'bucket_' || (abs(hashtext(lower(attribution_medium))::bigint) % 16)::text END,
  attribution_campaign = CASE WHEN attribution_campaign IS NULL THEN NULL
                              ELSE 'bucket_' || (abs(hashtext(lower(attribution_campaign))::bigint) % 16)::text END,
  attribution_content  = CASE WHEN attribution_content IS NULL THEN NULL
                              ELSE 'bucket_' || (abs(hashtext(lower(attribution_content))::bigint) % 16)::text END;

-- 3.2 phone_verifications ---------------------------------------------------
UPDATE phone_verifications SET
  phone       = '+99900000' || user_id,
  code_digest = 'redacted';

-- 3.3 push_tokens ---------------------------------------------------------
UPDATE push_tokens SET
  token       = 'snapshot-token-' || id,
  device_name = NULL,
  last_error  = CASE WHEN last_error IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.4 verification / trust ------------------------------------------------
UPDATE verification_checks SET
  provider          = NULL,
  provider_reference = NULL,
  rejection_code    = NULL,
  ai_review_model   = NULL,
  ai_review_error   = NULL,
  ai_review_result  = '{}'::jsonb;

UPDATE verification_events SET metadata = '{}'::jsonb;

UPDATE selfie_verifications SET
  rejection_reason = CASE WHEN rejection_reason IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE trust_events SET
  idempotency_key = 'snapshot-te-' || id,
  metadata        = '{}'::jsonb;

UPDATE trust_adjustments SET
  idempotency_key = 'snapshot-ta-' || id,
  note            = CASE WHEN note IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.5 media metadata (no bytes; keys/filenames are access identifiers) ----
UPDATE active_storage_blobs SET
  key      = 'snapshot/' || id || '/' || md5(id::text || :'salt'),
  filename = 'file-' || id ||
             CASE WHEN content_type IS NULL THEN ''
                  ELSE '.' || regexp_replace(split_part(content_type, '/', 2), '[^a-z0-9]', '', 'g') END,
  metadata = NULL;

UPDATE profile_videos SET
  rejection_reason = CASE WHEN rejection_reason IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.6 dating graph -------------------------------------------------------
UPDATE messages SET
  body = CASE WHEN body IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE reports SET
  body = CASE WHEN body IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE daily_introductions SET
  compatibility_reasons = '[]'::jsonb;

-- 3.7 notifications ----------------------------------------------------
UPDATE notifications SET payload = '{}'::jsonb;

UPDATE notification_deliveries SET
  last_error = CASE WHEN last_error IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.8 community ------------------------------------------------------
UPDATE community_questions SET
  body            = '[redacted]',
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END,
  aunty_phobie_take = CASE WHEN aunty_phobie_take IS NULL THEN NULL ELSE '[redacted]' END,
  risk_flags      = '[]'::jsonb;

UPDATE community_answers SET
  body            = '[redacted]',
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END,
  risk_flags      = '[]'::jsonb;

UPDATE community_remarks SET
  body            = '[redacted]',
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END,
  risk_flags      = '[]'::jsonb;

UPDATE community_events SET
  title           = 'Event ' || id,
  description     = '[redacted]',
  venue           = NULL,                 -- nullable
  city            = '[redacted]',         -- NOT NULL: cannot drop
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END,
  risk_flags      = '[]'::jsonb;

UPDATE community_stories SET
  couple_names    = 'Couple ' || id,
  title           = 'Story ' || id,
  location        = NULL,
  body            = '[redacted]',
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END,
  risk_flags      = '[]'::jsonb;

UPDATE community_reports SET
  body            = CASE WHEN body IS NULL THEN NULL ELSE '[redacted]' END,
  moderation_note = CASE WHEN moderation_note IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.9 dating hub / personas / journals --------------------------------
UPDATE personas SET
  current_life      = CASE WHEN current_life IS NULL THEN NULL ELSE '[redacted]' END,
  family_background = CASE WHEN family_background IS NULL THEN NULL ELSE '[redacted]' END,
  looking_for       = CASE WHEN looking_for IS NULL THEN NULL ELSE '[redacted]' END,
  core_values           = '{}'::character varying[],
  hobbies_and_interests = '{}'::character varying[],
  good_stories          = '{}'::character varying[],
  topics_to_ease_into   = '{}'::character varying[];

UPDATE dating_hub_batches SET
  name        = 'Batch ' || id,
  description = CASE WHEN description IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE tracked_contacts SET
  external_name          = CASE WHEN external_name IS NULL THEN NULL ELSE 'Contact ' || id END,
  external_location      = NULL,
  partner_birthday_month = NULL,
  partner_birthday_day   = NULL;

UPDATE tracked_contact_notes SET body = '[redacted]';

UPDATE daily_life_entries SET
  today_plan   = CASE WHEN today_plan IS NULL THEN NULL ELSE '[redacted]' END,
  highlight    = CASE WHEN highlight IS NULL THEN NULL ELSE '[redacted]' END,
  learned      = CASE WHEN learned IS NULL THEN NULL ELSE '[redacted]' END,
  ask_prompt   = CASE WHEN ask_prompt IS NULL THEN NULL ELSE '[redacted]' END,
  share_prompt = CASE WHEN share_prompt IS NULL THEN NULL ELSE '[redacted]' END,
  mood         = CASE WHEN mood IS NULL THEN NULL ELSE '[redacted]' END,
  focus_tag    = CASE WHEN focus_tag IS NULL THEN NULL ELSE '[redacted]' END;

-- 3.10 aunty phobie -------------------------------------------------
UPDATE aunty_phobie_messages SET
  content          = '[redacted]',
  context_snapshot = '{}'::jsonb,
  client_message_id = CASE WHEN client_message_id IS NULL THEN NULL ELSE 'snapshot-cm-' || id END;

UPDATE aunty_phobie_conversations SET
  escalation_resolution_note =
    CASE WHEN escalation_resolution_note IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE aunty_phobie_usage_events SET request_key = 'snapshot-rk-' || id;

-- 3.11 careers / feedback / ops / company --------------------------
UPDATE career_applications SET
  name          = 'Snapshot Applicant ' || id,
  email         = 'applicant+' || id || '@snapshot.invalid',
  phone         = CASE WHEN phone IS NULL THEN NULL ELSE '+99900000' || id END,
  date9ja_email = CASE WHEN date9ja_email IS NULL THEN NULL
                       ELSE 'date9ja+' || coalesce(user_id, id) || '@snapshot.invalid' END,
  cover_letter  = '[redacted]',
  portfolio_url = CASE WHEN portfolio_url IS NULL THEN NULL ELSE 'https://snapshot.invalid/' || id END,
  linkedin_url  = CASE WHEN linkedin_url IS NULL THEN NULL ELSE 'https://snapshot.invalid/' || id END,
  admin_note    = CASE WHEN admin_note IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE feedback_items SET message = '[redacted]';

-- career_jobs are company-authored postings, not migration data. Redact the
-- long free-text fields defensively — a shareable snapshot must not carry
-- internal wording / staff names an unpublished draft might contain. Structural
-- fields (title, slug, department, location, employment_type, status, dates)
-- are non-sensitive and stay. Reviewer decision, R5.
UPDATE career_jobs SET
  summary          = '[redacted]',
  description      = '[redacted]',
  responsibilities = '[redacted]',
  requirements     = '[redacted]',
  nice_to_have     = CASE WHEN nice_to_have IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE error_logs SET
  message      = CASE WHEN message IS NULL THEN NULL ELSE '[redacted]' END,
  backtrace    = CASE WHEN backtrace IS NULL THEN NULL ELSE '[redacted]' END,
  request_path = CASE WHEN request_path IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE audit_logs SET metadata = '{}'::jsonb;

UPDATE company_journal_entries SET
  title = '[redacted]',
  note  = CASE WHEN note IS NULL THEN NULL ELSE '[redacted]' END;

UPDATE company_settings SET
  mission         = CASE WHEN mission IS NULL THEN NULL ELSE '[redacted]' END,
  vision          = CASE WHEN vision IS NULL THEN NULL ELSE '[redacted]' END,
  advisor_summary = CASE WHEN advisor_summary IS NULL THEN NULL ELSE '[redacted]' END,
  advisor_why     = CASE WHEN advisor_why IS NULL THEN NULL ELSE '[redacted]' END,
  advisor_error   = CASE WHEN advisor_error IS NULL THEN NULL ELSE '[redacted]' END,
  advisor_focus_areas = '[]'::jsonb;

-- =============================================================================
-- 4. INLINE POST-CHECKS (fail-closed; abort transaction on any violation)
--    The standalone verifier repeats and extends these; this block guarantees
--    a bad run never commits even if the operator forgets to run the verifier.
-- =============================================================================
DO $post$
DECLARE
  n bigint;
BEGIN
  -- counts unchanged
  IF (SELECT count(*) FROM users) <> (SELECT value FROM sanitize_audit.counts WHERE metric='users') THEN
    RAISE EXCEPTION 'POST-CHECK: users row count changed';
  END IF;
  IF (SELECT count(*) FROM messages) <> (SELECT value FROM sanitize_audit.counts WHERE metric='messages') THEN
    RAISE EXCEPTION 'POST-CHECK: messages row count changed';
  END IF;
  IF (SELECT count(*) FROM active_storage_blobs) <> (SELECT value FROM sanitize_audit.counts WHERE metric='active_storage_blobs') THEN
    RAISE EXCEPTION 'POST-CHECK: active_storage_blobs row count changed';
  END IF;

  -- no real-looking emails
  SELECT count(*) INTO n FROM users WHERE email !~ '^date9ja\+[0-9]+@snapshot\.invalid$';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.email not in synthetic form', n; END IF;
  SELECT count(*) INTO n FROM users WHERE unconfirmed_email IS NOT NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.unconfirmed_email not null', n; END IF;

  -- no auth secrets
  SELECT count(*) INTO n FROM users WHERE reset_password_token IS NOT NULL OR confirmation_token IS NOT NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users still carry reset/confirmation tokens', n; END IF;
  SELECT count(*) INTO n FROM users WHERE jti !~ '^snapshot-';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.jti not neutralised', n; END IF;
  SELECT count(*) INTO n FROM users WHERE current_sign_in_ip IS NOT NULL OR last_sign_in_ip IS NOT NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users still carry IP addresses', n; END IF;
  SELECT count(*) INTO n FROM users WHERE encrypted_password <> '$2a$12$3Jgn6erKwDc0ADnT4arvEOi.EuOE00NCLVpYHtmVAs39f9I2WJbbm';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.encrypted_password not the inert digest', n; END IF;

  -- phones non-routable
  SELECT count(*) INTO n FROM users WHERE phone IS NOT NULL AND phone !~ '^\+999';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.phone look routable', n; END IF;
  SELECT count(*) INTO n FROM phone_verifications WHERE phone !~ '^\+999' OR code_digest <> 'redacted';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % phone_verifications not sanitised', n; END IF;

  -- push tokens
  SELECT count(*) INTO n FROM push_tokens WHERE token !~ '^snapshot-token-';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % push_tokens.token not neutralised', n; END IF;

  -- verification provider / AI evidence
  SELECT count(*) INTO n FROM verification_checks
   WHERE provider IS NOT NULL OR provider_reference IS NOT NULL
      OR ai_review_model IS NOT NULL OR ai_review_error IS NOT NULL
      OR ai_review_result <> '{}'::jsonb;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % verification_checks still carry provider/AI evidence', n; END IF;

  -- redacted jsonb columns
  SELECT count(*) INTO n FROM notifications WHERE payload <> '{}'::jsonb;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % notifications.payload not redacted', n; END IF;
  SELECT count(*) INTO n FROM audit_logs WHERE metadata <> '{}'::jsonb;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % audit_logs.metadata not redacted', n; END IF;
  SELECT count(*) INTO n FROM users WHERE v2_onboarding_answers <> '{}'::jsonb;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.v2_onboarding_answers not redacted', n; END IF;

  -- redacted text columns
  SELECT count(*) INTO n FROM messages WHERE body IS NOT NULL AND body <> '[redacted]';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % messages.body not redacted', n; END IF;
  SELECT count(*) INTO n FROM aunty_phobie_messages WHERE content <> '[redacted]';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % aunty_phobie_messages.content not redacted', n; END IF;

  -- generalisation
  SELECT count(*) INTO n FROM users
   WHERE date_of_birth IS NOT NULL AND (extract(month FROM date_of_birth) <> 7 OR extract(day FROM date_of_birth) <> 1);
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.date_of_birth not generalised to 1 Jul', n; END IF;
  SELECT count(*) INTO n FROM users
   WHERE location_latitude IS NOT NULL OR location_longitude IS NOT NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users still carry coordinates', n; END IF;

  SELECT count(*) INTO n FROM users u
   WHERE EXISTS (SELECT 1 FROM jsonb_each(u.notification_preferences) e
                 WHERE jsonb_typeof(e.value) <> 'boolean')
      OR EXISTS (SELECT 1 FROM jsonb_each(u.email_notification_preferences) e
                 WHERE jsonb_typeof(e.value) <> 'boolean');
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users have non-boolean notification-preference values', n; END IF;

  -- legacy IDs + determinism
  SELECT count(*) INTO n FROM users
   WHERE email <> 'date9ja+' || id || '@snapshot.invalid';
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % users.email not deterministic from id', n; END IF;
  IF (SELECT count(DISTINCT id) FROM users) <> (SELECT count(DISTINCT public_id) FROM users)
     OR (SELECT count(DISTINCT id) FROM users) <> (SELECT count(DISTINCT email) FROM users) THEN
    RAISE EXCEPTION 'POST-CHECK: users id/public_id/email cardinality diverged';
  END IF;

  -- orphan core FKs (spot set)
  SELECT count(*) INTO n FROM messages m LEFT JOIN matches mt ON mt.id = m.match_id WHERE mt.id IS NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % orphan messages', n; END IF;
  SELECT count(*) INTO n FROM active_storage_attachments a
    LEFT JOIN active_storage_blobs b ON b.id = a.blob_id WHERE b.id IS NULL;
  IF n > 0 THEN RAISE EXCEPTION 'POST-CHECK: % orphan attachments', n; END IF;

  RAISE NOTICE 'inline post-checks passed';
END
$post$;

COMMIT;

\echo '========================================================================'
\echo ' sanitize_snapshot.sql committed. Now run:'
\echo '   psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \\'
\echo '        -f scripts/date9ja/verify_sanitized_snapshot.sql'
\echo '========================================================================'
