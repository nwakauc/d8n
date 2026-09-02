-- =============================================================================
-- Date9ja sanitized-snapshot verifier
-- =============================================================================
-- Authority: docs/migrations/date9ja-to-d8n/SANITIZATION-CONTRACT.md §7
-- Run AFTER scripts/date9ja/sanitize_snapshot.sql, against the same database:
--
--   psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
--        -f scripts/date9ja/verify_sanitized_snapshot.sql
--
-- Read-only. Collects every invariant violation, prints them, and RAISEs
-- (non-zero exit under ON_ERROR_STOP) if any are found. Prints the documented
-- 2026-09-02 baseline row counts for information only — a different future
-- snapshot may legitimately differ, so a baseline mismatch is a NOTICE, not a
-- failure. What IS enforced: row counts are unchanged relative to the values
-- the sanitizer captured before it ran (sanitize_audit.counts).
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Schema guard (identical to the sanitizer)
-- ---------------------------------------------------------------------------
DO $schema$
DECLARE
  v_tables int;
  v_fp     text;
BEGIN
  SELECT count(*) INTO v_tables
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
  IF v_tables <> 51 THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: expected 51 public base tables, found %', v_tables;
  END IF;

  SELECT md5(string_agg(table_name || '.' || column_name, ','
                        ORDER BY (table_name || '.' || column_name) COLLATE "C"))
    INTO v_fp
  FROM information_schema.columns
  WHERE table_schema = 'public';
  IF v_fp IS DISTINCT FROM 'a317e7fb66f0d304e6273a4ee2473172' THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: column fingerprint % unexpected', v_fp;
  END IF;
END
$schema$;

-- ---------------------------------------------------------------------------
-- Pre-run count table must exist (proves the sanitizer ran)
-- ---------------------------------------------------------------------------
DO $pre$
BEGIN
  IF to_regclass('sanitize_audit.counts') IS NULL THEN
    RAISE EXCEPTION 'sanitize_audit.counts is missing — run sanitize_snapshot.sql first';
  END IF;
END
$pre$;

-- ---------------------------------------------------------------------------
-- Informational baseline (2026-09-02) — NOTICE only
-- ---------------------------------------------------------------------------
DO $baseline$
DECLARE
  r          record;
  v_expected jsonb := '{
    "users":288,"photos":279,"profile_videos":35,"active_storage_blobs":443,
    "likes":546,"matches":82,"messages":1025,"profile_views":1627,
    "blocks":3,"reports":3 }'::jsonb;
  k text;
  v_now bigint;
BEGIN
  FOR k IN SELECT jsonb_object_keys(v_expected) LOOP
    EXECUTE format('SELECT count(*) FROM %I', k) INTO v_now;
    IF v_now <> (v_expected->>k)::bigint THEN
      RAISE NOTICE 'baseline drift (informational): % is % now, 2026-09-02 baseline was %',
        k, v_now, v_expected->>k;
    END IF;
  END LOOP;
END
$baseline$;

-- ---------------------------------------------------------------------------
-- Enforced invariants
-- ---------------------------------------------------------------------------
DO $verify$
DECLARE
  fails text[] := ARRAY[]::text[];
  n     bigint;
  ref text;
BEGIN
  -- 1. row counts unchanged vs. the sanitizer's pre-run capture
  FOR ref IN
    SELECT metric FROM sanitize_audit.counts WHERE metric <> 'run_at_epoch'
  LOOP
    EXECUTE format('SELECT count(*) FROM %I', ref) INTO n;
    IF n <> (SELECT value FROM sanitize_audit.counts WHERE metric = ref) THEN
      fails := fails || format('row count for %s changed after sanitize (%s vs %s captured)',
        ref, n,
        (SELECT value FROM sanitize_audit.counts WHERE metric = ref));
    END IF;
  END LOOP;

  -- 2. emails
  SELECT count(*) INTO n FROM users WHERE email !~ '^date9ja\+[0-9]+@snapshot\.invalid$';
  IF n > 0 THEN fails := fails || format('%s users.email not synthetic', n); END IF;

  SELECT count(*) INTO n FROM users WHERE unconfirmed_email IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users.unconfirmed_email not null', n); END IF;

  SELECT count(*) INTO n FROM career_applications
   WHERE email !~ '@snapshot\.invalid$'
      OR (date9ja_email IS NOT NULL AND date9ja_email !~ '@snapshot\.invalid$');
  IF n > 0 THEN fails := fails || format('%s career_applications carry a non-synthetic email', n); END IF;

  -- generic "looks like a real email anywhere it should not" sweeps
  SELECT count(*) INTO n FROM users
   WHERE full_name ~ '@' OR display_name ~ '@' OR about_me ~ '@'
      OR ideal_partner_description ~ '@' OR occupation ~ '@';
  IF n > 0 THEN fails := fails || format('%s users have an "@" in a redacted/name field', n); END IF;

  -- 3. auth secrets
  SELECT count(*) INTO n FROM users WHERE reset_password_token IS NOT NULL OR confirmation_token IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users carry reset/confirmation tokens', n); END IF;

  SELECT count(*) INTO n FROM users WHERE jti !~ '^snapshot-';
  IF n > 0 THEN fails := fails || format('%s users.jti not neutralised', n); END IF;

  SELECT count(*) INTO n FROM users
   WHERE encrypted_password <> '$2a$12$3Jgn6erKwDc0ADnT4arvEOi.EuOE00NCLVpYHtmVAs39f9I2WJbbm';
  IF n > 0 THEN fails := fails || format('%s users.encrypted_password not the single inert digest', n); END IF;

  SELECT count(*) INTO n FROM users WHERE current_sign_in_ip IS NOT NULL OR last_sign_in_ip IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users carry IP addresses', n); END IF;

  -- 4. phones (non-routable +999 or null)
  SELECT count(*) INTO n FROM users WHERE phone IS NOT NULL AND phone !~ '^\+999[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s users.phone not the +999 non-routable form', n); END IF;
  SELECT count(*) INTO n FROM phone_verifications WHERE phone !~ '^\+999[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s phone_verifications.phone not +999 form', n); END IF;
  SELECT count(*) INTO n FROM phone_verifications WHERE code_digest <> 'redacted';
  IF n > 0 THEN fails := fails || format('%s phone_verifications.code_digest not destroyed', n); END IF;
  SELECT count(*) INTO n FROM career_applications WHERE phone IS NOT NULL AND phone !~ '^\+999[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s career_applications.phone not +999 form', n); END IF;

  -- 5. push tokens / device
  SELECT count(*) INTO n FROM push_tokens WHERE token !~ '^snapshot-token-[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s push_tokens.token not neutralised', n); END IF;
  SELECT count(*) INTO n FROM push_tokens WHERE device_name IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s push_tokens.device_name not destroyed', n); END IF;

  -- 6. verification provider / evidence / AI payloads
  SELECT count(*) INTO n FROM verification_checks
   WHERE provider IS NOT NULL OR provider_reference IS NOT NULL
      OR rejection_code IS NOT NULL OR ai_review_model IS NOT NULL
      OR ai_review_error IS NOT NULL OR ai_review_result <> '{}'::jsonb;
  IF n > 0 THEN fails := fails || format('%s verification_checks retain provider/evidence/AI data', n); END IF;

  -- 7. idempotency keys neutralised
  SELECT count(*) INTO n FROM trust_events WHERE idempotency_key !~ '^snapshot-te-[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s trust_events.idempotency_key not neutralised', n); END IF;
  SELECT count(*) INTO n FROM trust_adjustments WHERE idempotency_key !~ '^snapshot-ta-[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s trust_adjustments.idempotency_key not neutralised', n); END IF;
  SELECT count(*) INTO n FROM aunty_phobie_usage_events WHERE request_key !~ '^snapshot-rk-[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s aunty_phobie_usage_events.request_key not neutralised', n); END IF;

  -- 8. media identifiers
  SELECT count(*) INTO n FROM active_storage_blobs WHERE key !~ '^snapshot/[0-9]+/[0-9a-f]{32}$';
  IF n > 0 THEN fails := fails || format('%s active_storage_blobs.key not a fake deterministic key', n); END IF;
  SELECT count(*) INTO n FROM active_storage_blobs WHERE filename !~ '^file-[0-9]+';
  IF n > 0 THEN fails := fails || format('%s active_storage_blobs.filename not neutralised', n); END IF;
  SELECT count(*) INTO n FROM active_storage_blobs WHERE metadata IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s active_storage_blobs.metadata not cleared', n); END IF;

  -- 9. free-text REDACT columns: value must be NULL or exactly '[redacted]'
  FOR ref IN SELECT unnest(ARRAY[
      'messages.body','reports.body','community_reports.body','community_questions.body',
      'community_answers.body','community_remarks.body','community_stories.body',
      'community_events.description','community_questions.aunty_phobie_take',
      'community_questions.moderation_note','community_answers.moderation_note',
      'community_remarks.moderation_note','community_events.moderation_note',
      'community_stories.moderation_note','community_reports.moderation_note',
      'aunty_phobie_messages.content','aunty_phobie_conversations.escalation_resolution_note',
      'tracked_contact_notes.body','tracked_contacts.external_location',
      'dating_hub_batches.description','daily_life_entries.today_plan',
      'daily_life_entries.highlight','daily_life_entries.learned','daily_life_entries.ask_prompt',
      'daily_life_entries.share_prompt','daily_life_entries.mood','daily_life_entries.focus_tag',
      'feedback_items.message','personas.current_life',
      'personas.family_background','personas.looking_for','error_logs.message',
      'error_logs.backtrace','error_logs.request_path','users.about_me',
      'users.ideal_partner_description',
      'users.interest_in_nigerian_culture','users.occupation','users.deletion_reason',
      'users.suspension_reason','users.ban_reason','profile_videos.rejection_reason',
      'selfie_verifications.rejection_reason','trust_adjustments.note',
      'notification_deliveries.last_error','push_tokens.last_error',
      'career_applications.cover_letter','career_applications.admin_note',
      'career_jobs.summary','career_jobs.description','career_jobs.responsibilities',
      'career_jobs.requirements','career_jobs.nice_to_have',
      'company_journal_entries.title','company_journal_entries.note',
      'company_settings.mission','company_settings.vision','company_settings.advisor_summary',
      'company_settings.advisor_why','company_settings.advisor_error' ])
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I WHERE %I IS NOT NULL AND %I <> ''[redacted]''',
      split_part(ref,'.',1), split_part(ref,'.',2), split_part(ref,'.',2))
      INTO n;
    IF n > 0 THEN fails := fails || format('%s rows in %s still hold raw text', n, ref); END IF;
  END LOOP;

  -- 10. object-shaped jsonb REDACT columns must equal '{}'
  FOR ref IN SELECT unnest(ARRAY[
      'notifications.payload','audit_logs.metadata','trust_events.metadata',
      'verification_events.metadata','verification_checks.ai_review_result',
      'aunty_phobie_messages.context_snapshot','users.v2_onboarding_answers' ])
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE %I <> ''{}''::jsonb',
      split_part(ref,'.',1), split_part(ref,'.',2)) INTO n;
    IF n > 0 THEN fails := fails || format('%s rows in %s not {} jsonb', n, ref); END IF;
  END LOOP;

  -- array-shaped jsonb REDACT columns must equal '[]'
  FOR ref IN SELECT unnest(ARRAY[
      'community_questions.risk_flags','community_answers.risk_flags',
      'community_remarks.risk_flags','community_events.risk_flags',
      'community_stories.risk_flags','daily_introductions.compatibility_reasons',
      'company_settings.advisor_focus_areas' ])
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE %I <> ''[]''::jsonb',
      split_part(ref,'.',1), split_part(ref,'.',2)) INTO n;
    IF n > 0 THEN fails := fails || format('%s rows in %s not [] jsonb', n, ref); END IF;
  END LOOP;

  -- redacted varchar[] must be empty
  FOR ref IN SELECT unnest(ARRAY[
      'users.preferred_religion','users.preferred_tribes','users.interests',
      'users.relationship_values','users.dealbreakers','personas.core_values',
      'personas.hobbies_and_interests','personas.good_stories','personas.topics_to_ease_into' ])
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE cardinality(%I) > 0',
      split_part(ref,'.',1), split_part(ref,'.',2)) INTO n;
    IF n > 0 THEN fails := fails || format('%s rows in %s still populated', n, ref); END IF;
  END LOOP;

  -- 11. generalisation
  SELECT count(*) INTO n FROM users
   WHERE date_of_birth IS NOT NULL
     AND (extract(month FROM date_of_birth) <> 7 OR extract(day FROM date_of_birth) <> 1);
  IF n > 0 THEN fails := fails || format('%s users.date_of_birth not generalised to 01 Jul', n); END IF;

  SELECT count(*) INTO n FROM users
   WHERE (location_latitude  IS NOT NULL AND location_latitude  <> round(location_latitude, 1))
      OR (location_longitude IS NOT NULL AND location_longitude <> round(location_longitude, 1));
  IF n > 0 THEN fails := fails || format('%s users have finer-than-0.1-degree coordinates', n); END IF;

  SELECT count(*) INTO n FROM users WHERE city IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users.city not cleared', n); END IF;

  SELECT count(*) INTO n FROM users
   WHERE location_latitude IS NOT NULL OR location_longitude IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users still carry coordinates', n); END IF;

  -- sensitive religious/ethnic/tribal attributes must be fully dropped (R1)
  SELECT count(*) INTO n FROM users
   WHERE tribe IS NOT NULL OR denomination IS NOT NULL OR state_of_origin IS NOT NULL
      OR nationality IS NOT NULL OR religion IS NOT NULL OR ethnicity IS NOT NULL
      OR intertribal_marriage_openness IS NOT NULL OR polygamy_openness IS NOT NULL
      OR is_nigerian IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s users retain a sensitive religious/ethnic/tribal attribute', n); END IF;

  -- attribution / signup source must be bucketised or null
  FOR ref IN SELECT unnest(ARRAY['signup_source','attribution_source','attribution_medium',
      'attribution_campaign','attribution_content']) LOOP
    EXECUTE format('SELECT count(*) FROM users WHERE %I IS NOT NULL AND %I !~ ''^bucket_[0-9]+$''',
      ref, ref) INTO n;
    IF n > 0 THEN fails := fails || format('%s users.%s not bucketised', n, ref); END IF;
  END LOOP;

  -- notification-preference JSON: every value must be a JSON boolean
  SELECT count(*) INTO n FROM users u
   WHERE EXISTS (SELECT 1 FROM jsonb_each(u.notification_preferences) e WHERE jsonb_typeof(e.value) <> 'boolean')
      OR EXISTS (SELECT 1 FROM jsonb_each(u.email_notification_preferences) e WHERE jsonb_typeof(e.value) <> 'boolean');
  IF n > 0 THEN fails := fails || format('%s users have a non-boolean notification-preference value', n); END IF;

  -- pseudonymised names / titles must be the deterministic synthetic form
  SELECT count(*) INTO n FROM users WHERE full_name !~ '^Snapshot User [0-9]+$' OR display_name !~ '^Snapshot [0-9]+$';
  IF n > 0 THEN fails := fails || format('%s users.full_name/display_name not synthetic', n); END IF;
  SELECT count(*) INTO n FROM tracked_contacts WHERE external_name IS NOT NULL AND external_name !~ '^Contact [0-9]+$';
  IF n > 0 THEN fails := fails || format('%s tracked_contacts.external_name not synthetic', n); END IF;
  SELECT count(*) INTO n FROM tracked_contacts WHERE partner_birthday_month IS NOT NULL OR partner_birthday_day IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s tracked_contacts still carry a partner birthday', n); END IF;
  SELECT count(*) INTO n FROM community_stories WHERE couple_names !~ '^Couple [0-9]+$' OR title !~ '^Story [0-9]+$';
  IF n > 0 THEN fails := fails || format('%s community_stories.couple_names/title not synthetic', n); END IF;
  SELECT count(*) INTO n FROM community_events WHERE title !~ '^Event [0-9]+$';
  IF n > 0 THEN fails := fails || format('%s community_events.title not synthetic', n); END IF;
  SELECT count(*) INTO n FROM community_events WHERE venue IS NOT NULL OR city <> '[redacted]';
  IF n > 0 THEN fails := fails || format('%s community_events retain venue/city', n); END IF;
  SELECT count(*) INTO n FROM community_stories WHERE location IS NOT NULL;
  IF n > 0 THEN fails := fails || format('%s community_stories.location retained', n); END IF;
  SELECT count(*) INTO n FROM dating_hub_batches WHERE name !~ '^Batch [0-9]+$';
  IF n > 0 THEN fails := fails || format('%s dating_hub_batches.name not synthetic', n); END IF;
  SELECT count(*) INTO n FROM career_applications
   WHERE name !~ '^Snapshot Applicant [0-9]+$'
      OR (portfolio_url IS NOT NULL AND portfolio_url !~ '^https://snapshot\.invalid/')
      OR (linkedin_url  IS NOT NULL AND linkedin_url  !~ '^https://snapshot\.invalid/');
  IF n > 0 THEN fails := fails || format('%s career_applications identity/URLs not synthetic', n); END IF;
  SELECT count(*) INTO n FROM aunty_phobie_messages
   WHERE client_message_id IS NOT NULL AND client_message_id !~ '^snapshot-cm-[0-9]+$';
  IF n > 0 THEN fails := fails || format('%s aunty_phobie_messages.client_message_id not neutralised', n); END IF;

  -- broad "@" sweep across every remaining user-facing text column
  SELECT count(*) INTO n FROM users
   WHERE full_name ~ '@' OR display_name ~ '@' OR occupation ~ '@'
      OR about_me ~ '@' OR ideal_partner_description ~ '@' OR interest_in_nigerian_culture ~ '@'
      OR country_of_residence ~ '@' OR body_type ~ '@';
  IF n > 0 THEN fails := fails || format('%s users rows have an "@" in a text field', n); END IF;

  -- 12. legacy IDs + determinism
  SELECT count(*) INTO n FROM users WHERE email <> 'date9ja+' || id || '@snapshot.invalid';
  IF n > 0 THEN fails := fails || format('%s users.email not deterministic from id', n); END IF;

  IF (SELECT count(DISTINCT id) FROM users) <> (SELECT count(*) FROM users)
     OR (SELECT count(DISTINCT public_id) FROM users) <> (SELECT count(*) FROM users)
     OR (SELECT count(DISTINCT email) FROM users) <> (SELECT count(*) FROM users)
     OR (SELECT count(*) FROM users WHERE phone IS NOT NULL) <>
        (SELECT count(DISTINCT phone) FROM users WHERE phone IS NOT NULL) THEN
    fails := fails || 'users id/public_id/email/phone uniqueness broken';
  END IF;

  -- 13. no orphaned core FKs
  SELECT count(*) INTO n FROM likes l
    LEFT JOIN users a ON a.id = l.liker_id LEFT JOIN users b ON b.id = l.liked_id
    WHERE a.id IS NULL OR b.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan likes', n); END IF;

  SELECT count(*) INTO n FROM matches m
    LEFT JOIN users a ON a.id = m.user_a_id LEFT JOIN users b ON b.id = m.user_b_id
    WHERE a.id IS NULL OR b.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan matches', n); END IF;

  SELECT count(*) INTO n FROM messages msg
    LEFT JOIN matches m ON m.id = msg.match_id LEFT JOIN users s ON s.id = msg.sender_id
    WHERE m.id IS NULL OR s.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan messages', n); END IF;

  SELECT count(*) INTO n FROM profile_views v
    LEFT JOIN users a ON a.id = v.viewer_id LEFT JOIN users b ON b.id = v.viewed_id
    WHERE a.id IS NULL OR b.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan profile_views', n); END IF;

  SELECT count(*) INTO n FROM photos p LEFT JOIN users u ON u.id = p.user_id WHERE u.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan photos', n); END IF;

  SELECT count(*) INTO n FROM profile_videos p LEFT JOIN users u ON u.id = p.user_id WHERE u.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan profile_videos', n); END IF;

  SELECT count(*) INTO n FROM active_storage_attachments att
    LEFT JOIN active_storage_blobs blb ON blb.id = att.blob_id WHERE blb.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan active_storage_attachments', n); END IF;

  SELECT count(*) INTO n FROM blocks bl
    LEFT JOIN users a ON a.id = bl.blocker_id LEFT JOIN users b ON b.id = bl.blocked_id
    WHERE a.id IS NULL OR b.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan blocks', n); END IF;

  SELECT count(*) INTO n FROM reports r
    LEFT JOIN users a ON a.id = r.reporter_id LEFT JOIN users b ON b.id = r.reported_id
    WHERE a.id IS NULL OR b.id IS NULL;
  IF n > 0 THEN fails := fails || format('%s orphan reports', n); END IF;

  -- 14. entitlement / verification state still present (nothing over-nulled)
  IF (SELECT count(*) FROM users WHERE subscription_status IS NULL) > 0
     OR (SELECT count(*) FROM users WHERE verification_tier IS NULL) > 0
     OR (SELECT count(*) FROM users WHERE trust_xp IS NULL) > 0
     OR (SELECT count(*) FROM users WHERE profile_completeness_score IS NULL) > 0 THEN
    fails := fails || 'a preserved user state column was nulled by the sanitizer';
  END IF;

  -- ---- verdict ----
  IF cardinality(fails) > 0 THEN
    RAISE EXCEPTION E'SANITIZATION VERIFICATION FAILED (% issue(s)):\n  - %',
      cardinality(fails), array_to_string(fails, E'\n  - ');
  END IF;

  RAISE NOTICE 'SANITIZATION VERIFICATION PASSED (0 violations)';
END
$verify$;

\echo '========================================================================'
\echo ' SANITIZATION VERIFICATION PASSED'
\echo ' Reminder: drop schema sanitize_audit before packaging the snapshot,'
\echo ' and follow SNAPSHOT-RUNBOOK.md for transfer / storage / deletion.'
\echo '========================================================================'
