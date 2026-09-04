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
end
