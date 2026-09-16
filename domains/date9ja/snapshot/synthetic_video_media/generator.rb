# frozen_string_literal: true

module Date9ja
  module Snapshot
    module SyntheticVideoMedia
      # Reads the ProfileVideo `video` blob rows from the media_v3 snapshot
      # database, renders a deterministic synthetic video for each into
      # `corpus_dir`, writes a PII-free manifest + fingerprint, and rewrites the
      # media_v3 blob `byte_size` / `checksum` so the artifact is internally
      # consistent with the synthetic bytes. Structural identity
      # (video/attachment/blob/owner ids, moderation, storage key, service_name,
      # content_type) is never changed.
      #
      #   Generator.new(connection: conn, corpus_dir: dir).call
      class Generator
        Result = Data.define(
          :object_count, :corpus_dir, :manifest_path, :manifest_fingerprint,
          :content_type_counts, :total_bytes, :patched_rows
        )

        BLOB_QUERY = <<~SQL
          SELECT b.id, b.key, b.content_type, b.service_name
          FROM active_storage_blobs b
          JOIN active_storage_attachments a ON a.blob_id = b.id
          WHERE a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}'
          ORDER BY b.id
        SQL

        def initialize(connection:, corpus_dir:, seed: DEFAULT_SEED, patch_metadata: true, schema_signature: nil)
          @connection = connection
          @corpus_dir = File.expand_path(corpus_dir)
          @seed = seed.to_s
          @patch_metadata = patch_metadata
          @schema_signature = schema_signature
        end

        def call
          FileUtils.mkdir_p(objects_dir)
          rows = @connection.exec_query(BLOB_QUERY).to_a.map { |row| row.transform_keys(&:to_s) }

          # Fail closed before a single object is written if any source key is
          # not the accepted safe-key contract.
          rows.each { |row| Date9ja::Storage::SafeObjectKey.validate!(row.fetch("key")) }

          objects = rows.map { |row| generate_one(row) }
          patched = @patch_metadata ? patch_metadata!(objects) : 0

          manifest = build_manifest(objects)
          File.write(manifest_path, "#{JSON.pretty_generate(manifest)}\n")
          fingerprint = fingerprint_of(manifest)
          File.write(fingerprint_path, "#{fingerprint}\n")

          Result.new(
            object_count: objects.size,
            corpus_dir: @corpus_dir,
            manifest_path:,
            manifest_fingerprint: fingerprint,
            content_type_counts: objects.group_by { |o| o[:canonical_content_type] }.transform_values(&:size),
            total_bytes: objects.sum { |o| o[:byte_size] },
            patched_rows: patched
          )
        end

        def manifest_path = File.join(@corpus_dir, "manifest.json")
        def fingerprint_path = File.join(@corpus_dir, "manifest.fingerprint")
        def objects_dir = File.join(@corpus_dir, "objects")

        # SHA256 over the reproducible content of a manifest (everything except
        # the wall-clock `generated_at_utc`). Stable across runs.
        def self.fingerprint_of(manifest)
          reproducible = manifest.slice("generator_version", "seed", "object_count", "objects")
          Digest::SHA256.hexdigest(JSON.generate(reproducible))
        end

        private

        def fingerprint_of(manifest) = self.class.fingerprint_of(manifest)

        def generate_one(row)
          blob_id = row.fetch("id").to_s
          content_type = row.fetch("content_type").to_s
          key = row.fetch("key").to_s

          render_plan = SyntheticVideoMedia.plan(
            source_blob_id: blob_id, canonical_content_type: content_type, seed: @seed
          )
          bytes = SyntheticVideoMedia.render(
            source_blob_id: blob_id, canonical_content_type: content_type, seed: @seed
          )
          path = Date9ja::Storage::SafeObjectKey.write_path_within(objects_dir, key)
          File.binwrite(path, bytes)

          {
            source_blob_id: blob_id,
            source_key: key,
            service_name: row.fetch("service_name").to_s,
            canonical_content_type: content_type,
            byte_size: bytes.bytesize,
            checksum: Digest::MD5.base64digest(bytes),
            container: render_plan[:container],
            expected_duration_seconds: render_plan[:duration_seconds],
            width: render_plan[:width],
            height: render_plan[:height],
            frame_rate: render_plan[:frame_rate],
            video_codec: render_plan[:video_codec],
            generator_version: GENERATOR_VERSION,
            seed: @seed,
            deterministic_identity: SyntheticVideoMedia.deterministic_identity(blob_id, content_type, @seed)
          }
        end

        def patch_metadata!(objects)
          count = 0
          @connection.transaction do
            objects.each do |o|
              # Both values are generated here — a computed integer and a base64
              # MD5 string. No external input reaches this statement.
              count += @connection.exec_update(
                "UPDATE active_storage_blobs SET byte_size = #{o[:byte_size].to_i}, " \
                "checksum = #{@connection.quote(o[:checksum])} " \
                "WHERE id = #{o[:source_blob_id].to_i}"
              )
            end
          end
          count
        end

        def build_manifest(objects)
          {
            "artifact" => ARTIFACT_NAME,
            "parent_artifact" => PARENT_ARTIFACT,
            "generator_version" => GENERATOR_VERSION,
            "seed" => @seed,
            "generated_at_utc" => Time.now.utc.iso8601,
            "parent_schema_signature" => @schema_signature,
            "evidence_rule" =>
              "SYNTHETIC engineering rehearsal media only. The sanitized snapshot does NOT contain the " \
              "legacy video bodies. This corpus proves NOTHING about the real videos' duration, codec or " \
              "container — those remain UNKNOWN until an authorized real-media rehearsal.",
            "lineage_note" =>
              "structural identity (video/attachment/blob/owner ids, moderation, storage key, service_name, " \
              "content_type) preserved from #{PARENT_ARTIFACT}; blob bytes are synthetic ffmpeg renders; " \
              "contains NO original Date9ja media bytes",
            "happy_path_max_duration_seconds" => MAX_DURATION_SECONDS,
            "object_count" => objects.size,
            "objects" => objects.sort_by { |o| o[:source_blob_id].to_i }.map { |o| o.transform_keys(&:to_s) }
          }
        end
      end
    end
  end
end
