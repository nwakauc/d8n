# frozen_string_literal: true

namespace :date9ja do
  desc "Rehearsal: Date9ja identity import against a restored scratch snapshot " \
       "(set DATE9JA_SNAPSHOT_DATABASE_URL). Prints a PII-free reconciliation JSON."
  task import_identity: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::UserSource.new(connection: connection)

    result = Date9ja::Import::IdentityImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: Date9ja profile & preference import (Pass 2) against a restored scratch " \
       "snapshot (set DATE9JA_SNAPSHOT_DATABASE_URL). Run AFTER date9ja:import_identity. " \
       "Creates ProfilePreference + option selections and decodes the legacy gender code; " \
       "publishes nothing and unhides nobody. Prints a PII-free reconciliation JSON."
  task import_profile_preferences: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::UserSource.new(connection: connection)

    result = Date9ja::Import::ProfilePreferenceImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: classify migrated Date9ja profile readiness against the restored scratch " \
       "snapshot. Run after identity, profile-preference, and media passes. Deterministic gaps " \
       "are filled without overwriting destination answers. DATE9JA_PUBLICATION_POLICY defaults " \
       "to classify_only; publish_visible_onboarded must not be used until D-8 is approved."
  task import_profile_readiness: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")
    publication_policy = ENV.fetch("DATE9JA_PUBLICATION_POLICY", "classify_only").to_sym

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::UserSource.new(connection: connection)

    result = Date9ja::Import::ProfileReadinessImport.call(
      brand:, source:, publication_policy:
    )

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: preserve the SENSITIVE Date9ja profile values (religion / tribe / ethnicity / " \
       "denomination / genotype / state_of_origin / nationality / is_nigerian / openness flags / " \
       "matching-preference arrays / interest_in_nigerian_culture) against the restored scratch " \
       "snapshot. Run AFTER date9ja:import_identity and date9ja:import_profile_preferences. Reads " \
       "ONLY the sensitive columns, through the dedicated SensitiveUserSource adapter. Gap-fill " \
       "only, owner-only destinations, fail closed. On the sanitized snapshot every value is " \
       "NULL/'{}' so this writes nothing. Prints a PII-free reconciliation JSON."
  task import_sensitive_profile: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::SensitiveUserSource.new(connection: connection)

    result = Date9ja::Import::SensitiveProfileImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Wave A Step 3 operator check: drive ALREADY-MIGRATED Date9ja accounts through the shared " \
       "D8N auth journey (login + brand session + cross-brand isolation + recovery→reset + " \
       "deactivate↔reactivate). Broad companion to scripts/date9ja/bcrypt_proof.rb (which proves " \
       "only the raw digest). Run LAST against a throwaway rehearsal DB after date9ja:import_identity " \
       "— it mutates the accounts it exercises. Set DATE9JA_AUTH_MANIFEST to an absolute TSV path: " \
       "identifier<TAB>password<TAB>lifecycle[<TAB>no_recovery] (lifecycle = active|suspended|" \
       "recovery_required; password empty for recovery_required; 4th column 'no_recovery' when the " \
       "account has no verified channel). Prints a PII-free JSON tally; exits non-zero on any failure."
  task verify_auth_transition: :environment do
    require "json"

    # Same throwaway-database contract as the VERIFIED bcrypt proof / identity
    # rehearsal (RAILS_ENV=test alone is not enough — the primary DB name must
    # match the accepted disposable pattern). Fails closed, no secret in the msg.
    begin
      Date9ja::Snapshot::Connection.assert_runtime_safe!
    rescue Date9ja::Snapshot::Connection::UnsafeConfiguration => e
      abort "refusing to run: #{e.message}"
    end

    path = ENV.fetch("DATE9JA_AUTH_MANIFEST", nil).to_s
    abort "DATE9JA_AUTH_MANIFEST must be set to an absolute path" unless File.absolute_path?(path) && File.file?(path)

    subjects =
      begin
        Date9ja::Import::AuthTransitionCheck.parse_manifest(File.readlines(path))
      rescue Date9ja::Import::AuthTransitionCheck::ManifestError => e
        abort "manifest: #{e.message}"
      end

    brand = Brand.kept.find_by!(slug: "date9ja")
    isolation_brand = Brand.kept.where.not(id: brand.id).where(status: :active).first

    result = Date9ja::Import::AuthTransitionCheck.call(brand:, subjects:, isolation_brand:)

    dump = JSON.pretty_generate(result.reconciliation.to_h)
    subjects.each do |s|
      dump = dump.gsub(s.identifier, "[redacted]")
      dump = dump.gsub(s.password, "[redacted]") if s.password
    end
    puts dump
    abort "AUTH TRANSITION: FAILURES PRESENT" unless result.all_passed?
    puts "AUTH TRANSITION: ALL CHECKS PASSED"
  end

  desc "Rehearsal: Date9ja profile-photo MEDIA PREFLIGHT (pass 1) against a restored scratch " \
       "snapshot (set DATE9JA_SNAPSHOT_DATABASE_URL). No byte transfer, no ProfilePhoto. " \
       "Prints a PII-free reconciliation JSON."
  task preflight_photos: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::PhotoSource.new(connection: connection)

    result = Date9ja::Import::PhotoImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: Date9ja profile-video MEDIA PREFLIGHT (pass 1) against a restored scratch " \
       "snapshot (set DATE9JA_SNAPSHOT_DATABASE_URL). No byte transfer, no ProfileVideo, no " \
       "playback/poster derivatives. Prints a PII-free reconciliation JSON."
  task preflight_videos: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::VideoSource.new(connection: connection)

    result = Date9ja::Import::VideoPreflight.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "L2 rehearsal: build the deterministic synthetic media corpus for " \
       "date9ja_snapshot_sanitized_media_v2. Set DATE9JA_SNAPSHOT_DATABASE_URL (the media_v2 DB) " \
       "and DATE9JA_MEDIA_CORPUS_DIR (output). Renders 279 synthetic images, writes a PII-free " \
       "manifest, and rewrites the media_v2 blob byte_size/checksum. Contains NO real Date9ja media."
  task build_media_v2: :environment do
    require "json"

    url = ENV.fetch("DATE9JA_SNAPSHOT_DATABASE_URL")
    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR")
    Date9ja::Snapshot::Connection.assert_safe!(url)

    signature = File.read(Rails.root.join("scripts/date9ja/schema_signature.sql"))[/v2 [0-9a-f]{32}/]

    Date9ja::Snapshot::Connection.establish_connection(url)
    connection = Date9ja::Snapshot::Connection.connection

    result = Date9ja::Snapshot::SyntheticMedia::Generator.new(
      connection:, corpus_dir:, schema_signature: signature
    ).call

    puts JSON.pretty_generate(
      "artifact" => Date9ja::Snapshot::SyntheticMedia::ARTIFACT_NAME,
      "object_count" => result.object_count,
      "content_type_counts" => result.content_type_counts,
      "total_corpus_bytes" => result.total_bytes,
      "patched_blob_rows" => result.patched_rows,
      "manifest_path" => result.manifest_path,
      "manifest_fingerprint" => result.manifest_fingerprint
    )
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "L2 rehearsal: verify the synthetic media corpus (15 checks) before Pass 2. " \
       "Set DATE9JA_SNAPSHOT_DATABASE_URL (media_v2), DATE9JA_SANITIZED_DATABASE_URL (parent), " \
       "DATE9JA_MEDIA_CORPUS_DIR, and optionally DATE9JA_MEDIA_CORPUS_DIR_2 for a byte-for-byte " \
       "determinism cross-check. Exits non-zero on any failed check."
  task verify_media_v2: :environment do
    require "json"

    v2_url = ENV.fetch("DATE9JA_SNAPSHOT_DATABASE_URL")
    parent_url = ENV.fetch("DATE9JA_SANITIZED_DATABASE_URL")
    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR")
    second_dir = ENV["DATE9JA_MEDIA_CORPUS_DIR_2"]
    Date9ja::Snapshot::Connection.assert_safe!(v2_url)
    Date9ja::Snapshot::Connection.assert_safe!(parent_url)

    manifest = JSON.parse(File.read(File.join(corpus_dir, "manifest.json")))

    # Two isolated read connections; the D8N primary (ActiveRecord::Base) is
    # never touched.
    Date9ja::Snapshot::Connection.establish_connection(v2_url)
    Date9ja::Snapshot::SanitizedParentConnection.connect!(url: parent_url)

    result = Date9ja::Snapshot::SyntheticMedia::Verifier.new(
      media_v2_connection: Date9ja::Snapshot::Connection.connection,
      parent_connection: Date9ja::Snapshot::SanitizedParentConnection.connection,
      corpus_dir:, manifest:, second_corpus_dir: second_dir
    ).call

    puts JSON.pretty_generate("ok" => result.ok?, "object_count" => result.object_count, "checks" => result.checks)
    abort "MEDIA_V2 ARTIFACT: VERIFICATION FAILED" unless result.ok?
    puts "MEDIA_V2 ARTIFACT: VERIFIED FOR L2"
  ensure
    Date9ja::Snapshot::SanitizedParentConnection.remove_connection
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "L2 rehearsal (ADR 0029 Pass 2C): build the deterministic synthetic VIDEO corpus for " \
       "date9ja_snapshot_sanitized_media_v3. Set DATE9JA_SNAPSHOT_DATABASE_URL (the media_v3 DB) and " \
       "DATE9JA_MEDIA_CORPUS_DIR (output). Renders 35 ffmpeg-generated synthetic videos (26 mp4 + 9 mov, " \
       "all <= 60s), writes a PII-free manifest + fingerprint, and rewrites the media_v3 blob " \
       "byte_size/checksum. Contains NO real Date9ja media and proves NOTHING about the real videos."
  task build_video_media_v3: :environment do
    require "json"

    url = ENV.fetch("DATE9JA_SNAPSHOT_DATABASE_URL")
    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR")
    Date9ja::Snapshot::Connection.assert_safe!(url)

    signature = File.read(Rails.root.join("scripts/date9ja/schema_signature.sql"))[/v2 [0-9a-f]{32}/]

    Date9ja::Snapshot::Connection.establish_connection(url)
    result = Date9ja::Snapshot::SyntheticVideoMedia::Generator.new(
      connection: Date9ja::Snapshot::Connection.connection, corpus_dir:, schema_signature: signature
    ).call

    puts JSON.pretty_generate(
      "artifact" => Date9ja::Snapshot::SyntheticVideoMedia::ARTIFACT_NAME,
      "object_count" => result.object_count,
      "content_type_counts" => result.content_type_counts,
      "total_corpus_bytes" => result.total_bytes,
      "patched_blob_rows" => result.patched_rows,
      "manifest_path" => result.manifest_path,
      "manifest_fingerprint" => result.manifest_fingerprint
    )
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "L2 rehearsal (ADR 0029 Pass 2C): verify the synthetic VIDEO corpus before Pass 2. " \
       "Set DATE9JA_SNAPSHOT_DATABASE_URL (media_v3), DATE9JA_SANITIZED_DATABASE_URL (parent), " \
       "DATE9JA_MEDIA_CORPUS_DIR, and optionally DATE9JA_MEDIA_CORPUS_DIR_2 for a byte-for-byte " \
       "determinism cross-check. Re-renders every body, walks each container, runs ffprobe, and " \
       "proves the media_v3 DB drifted from its parent ONLY in byte_size/checksum. Exits non-zero on any failed check."
  task verify_video_media_v3: :environment do
    require "json"

    v3_url = ENV.fetch("DATE9JA_SNAPSHOT_DATABASE_URL")
    parent_url = ENV.fetch("DATE9JA_SANITIZED_DATABASE_URL")
    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR")
    second_dir = ENV["DATE9JA_MEDIA_CORPUS_DIR_2"]
    Date9ja::Snapshot::Connection.assert_safe!(v3_url)
    Date9ja::Snapshot::Connection.assert_safe!(parent_url)

    manifest = JSON.parse(File.read(File.join(corpus_dir, "manifest.json")))

    Date9ja::Snapshot::Connection.establish_connection(v3_url)
    Date9ja::Snapshot::SanitizedParentConnection.connect!(url: parent_url)

    result = Date9ja::Snapshot::SyntheticVideoMedia::Verifier.new(
      media_v3_connection: Date9ja::Snapshot::Connection.connection,
      parent_connection: Date9ja::Snapshot::SanitizedParentConnection.connection,
      corpus_dir:, manifest:, second_corpus_dir: second_dir
    ).call

    puts JSON.pretty_generate("ok" => result.ok?, "object_count" => result.object_count, "checks" => result.checks)
    abort "MEDIA_V3 VIDEO ARTIFACT: VERIFICATION FAILED" unless result.ok?
    puts "MEDIA_V3 VIDEO ARTIFACT: VERIFIED FOR L2"
  ensure
    Date9ja::Snapshot::SanitizedParentConnection.remove_connection
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "L2 rehearsal: Date9ja profile-photo BYTE TRANSFER (pass 2) against the synthetic corpus. " \
       "Set DATE9JA_SNAPSHOT_DATABASE_URL (media_v2) and DATE9JA_MEDIA_CORPUS_DIR. ADR 0028. " \
       "Prints a PII-free reconciliation JSON. (L3 scoped-R2 transport is a later slice.)"
  task transfer_photos: :environment do
    require "json"

    corpus_dir = ENV.fetch(
      "DATE9JA_MEDIA_CORPUS_DIR",
      nil
    ) || abort("date9ja:transfer_photos (L2) requires DATE9JA_MEDIA_CORPUS_DIR (synthetic corpus). " \
               "L3 scoped read-only R2 transport is not wired in this build.")

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::PhotoSource.new(connection: connection)
    locator = Date9ja::Snapshot::MediaLocatorSource.new(connection: connection)
    reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir:)

    result = Date9ja::Import::PhotoTransfer.call(
      brand:, source:, locator:, source_reader: reader, processing: :inline
    )

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Date9ja profile-video BYTE TRANSFER pass 2A (ADR 0029): source bytes -> integrity + " \
       "container verification -> authoritative ffprobe duration -> Date9ja duration policy -> " \
       "deterministic destination ORIGINAL blob adoption. Creates NO ProfileVideo, NO profile_video " \
       "ReferenceMap binding, NO processing job (that is pass 2B). Set DATE9JA_SNAPSHOT_DATABASE_URL " \
       "and DATE9JA_MEDIA_CORPUS_DIR (synthetic corpus). Prints a PII-free reconciliation JSON."
  task transfer_videos_phase_a: :environment do
    require "json"

    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR", nil) ||
      abort("date9ja:transfer_videos_phase_a requires DATE9JA_MEDIA_CORPUS_DIR (synthetic corpus). " \
            "L3 scoped read-only R2 transport is not wired in this build.")

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::VideoSource.new(connection: connection)
    locator = Date9ja::Snapshot::VideoLocatorSource.new(connection: connection)
    reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir:)

    result = Date9ja::Import::VideoTransfer.call(brand:, source:, locator:, source_reader: reader, stage: :adopt)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Date9ja profile-video DOMAIN migration pass 2B (ADR 0029): adopted original blob -> " \
       "ProfileVideo + exact original attachment + Migration::ReferenceMap binding -> " \
       "Media::ProcessProfileVideoJob -> validated playback + poster -> ready -> existing raw purge. " \
       "Set DATE9JA_SNAPSHOT_DATABASE_URL and DATE9JA_MEDIA_CORPUS_DIR (synthetic corpus). " \
       "Prints a PII-free reconciliation JSON. (Full 35-video L2 corpus is pass 2C.)"
  task transfer_videos: :environment do
    require "json"

    corpus_dir = ENV.fetch("DATE9JA_MEDIA_CORPUS_DIR", nil) ||
      abort("date9ja:transfer_videos requires DATE9JA_MEDIA_CORPUS_DIR (synthetic corpus). " \
            "L3 scoped read-only R2 transport is not wired in this build.")

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::VideoSource.new(connection: connection)
    locator = Date9ja::Snapshot::VideoLocatorSource.new(connection: connection)
    reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir:)

    result = Date9ja::Import::VideoTransfer.call(
      brand:, source:, locator:, source_reader: reader, stage: :domain, processing: :inline
    )

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: import the retained Date9ja SOCIAL GRAPH / message history (likes, passes, " \
       "matches, conversations, messages, blocks, reports) against a restored scratch snapshot. " \
       "Run AFTER date9ja:import_identity. Historical rows only — no runtime notifications, quota, " \
       "or current timestamps. Prints a PII-free counts/reasons JSON."
  task import_historical_graph: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")
    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::HistoricalGraphSource.new(connection: connection)

    result = Date9ja::Import::HistoricalGraphImport.call(brand:, source:)
    puts JSON.pretty_generate("counts" => result.counts, "reasons" => result.reasons)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: import the Date9ja VERIFICATION / RealMe assurance history (verification_checks, " \
       "verification_events, legacy selfie_verifications) into private VerificationAssertion rows. " \
       "Run AFTER date9ja:import_identity. No evidence bytes, no public serializer exposure. " \
       "Prints a PII-free JSON tally."
  task import_verification: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")
    connection = Date9ja::Snapshot::Connection.connect!

    read = ->(table, cols) {
      present = connection.exec_query(
        "SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}'"
      ).rows.flatten
      selected = cols & present
      selected.empty? ? [] : connection.exec_query("SELECT #{selected.join(', ')} FROM #{table} ORDER BY id").to_a
    }

    result = Date9ja::Import::VerificationImport.call(
      brand:,
      checks: read.call("verification_checks",
        %w[id user_id kind check_type status submitted_at reviewed_at reviewer_id tier]),
      events: read.call("verification_events", %w[id user_id kind status created_at]),
      selfies: read.call("selfie_verifications", %w[id user_id status submitted_at reviewed_at])
    )
    puts JSON.pretty_generate("imported" => result.imported, "skipped" => result.skipped, "failed" => result.failed)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: import every retained Date9ja OPERATIONAL / MEMBER-VISIBLE history table that has " \
       "no dedicated D8N runtime aggregate (profile views, daily introductions, explore impressions, " \
       "notifications + deliveries, push tokens, Aunty Phobie history, community content/moderation, " \
       "trust ledgers, audit logs, exit attempts, feedback, persona, daily-life, tracked contacts/" \
       "notes) plus message reactions and the founding-member / premium / trust-XP entitlement " \
       "columns. Run AFTER date9ja:import_identity and date9ja:import_historical_graph. Prints a " \
       "PII-free per-entity reconciliation JSON."
  task import_extended_history: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")
    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::ExtendedHistorySource.new(connection: connection)

    result = Date9ja::Import::ExtendedHistoryImport.call(brand:, source:)
    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: preserve Date9ja LIFECYCLE / MODERATION context — soft-deleted members become " \
       "identity_tombstone ledger rows (no D8N User resurrected), retained members carrying a " \
       "suspension / ban / discovery restriction get a moderation_state row with reason/note/actor/" \
       "timestamps. Run AFTER date9ja:import_identity. Prints a PII-free reconciliation JSON."
  task import_lifecycle: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")
    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::LifecycleSource.new(connection: connection)

    result = Date9ja::Import::LifecycleImport.call(brand:, source:)
    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end
end
