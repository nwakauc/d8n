# frozen_string_literal: true

module Date9ja
  module Snapshot
    module SyntheticVideoMedia
      # Fail-closed pre-flight for the synthetic VIDEO corpus (ADR 0029 Pass 2C).
      # Independent of the generator: it re-derives every body from the
      # checked-in render function, independently inspects the bytes through the
      # shared runtime (Media::VideoContainerValidator + Media::VideoProcessor
      # ffprobe), and proves the media_v3 DB artifact drifted from its parent
      # ONLY in byte_size/checksum on the authorized ProfileVideo blob rows.
      #
      # Output is PII-free: check ids, counts, and mismatch shapes only.
      #
      #   Verifier.new(media_v3_connection: c1, parent_connection: c2,
      #                corpus_dir: dir, manifest:).call
      class Verifier
        Result = Data.define(:ok, :checks, :object_count) do
          def ok? = ok
          def failures = checks.reject { |c| c[:ok] }
        end

        VIDEO_KIND = Migration::MediaTransfer::MediaKind::Video

        VIDEO_STRUCT_SQL = <<~SQL
          SELECT v.id AS video_id, v.user_id, v.moderation_status,
                 a.id AS attachment_id, a.blob_id,
                 b.key, b.content_type, b.service_name
          FROM profile_videos v
          JOIN active_storage_attachments a
            ON a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}' AND a.record_id = v.id
          JOIN active_storage_blobs b ON b.id = a.blob_id
          ORDER BY v.id, a.id
        SQL

        AUTHORIZED_BLOB_IDS_SQL = <<~SQL
          SELECT a.blob_id
          FROM active_storage_attachments a
          WHERE a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}'
          ORDER BY a.blob_id
        SQL

        BLOB_COLUMNS_SQL = <<~SQL
          SELECT column_name FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'active_storage_blobs'
          ORDER BY ordinal_position
        SQL

        MUTABLE_COLUMNS = %w[byte_size checksum].freeze
        # The sanitized census: 35 ProfileVideo records (26 mp4 + 9 mov).
        EXPECTED_AUTHORIZED_COUNT = 35
        DURATION_TOLERANCE_SECONDS = 0.75

        ATTACHMENT_COLUMNS_SQL = <<~SQL
          SELECT column_name FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'active_storage_attachments'
          ORDER BY ordinal_position
        SQL

        # Tables the docs claim are unchanged (review Finding 2). The generator's
        # ONLY write is `UPDATE active_storage_blobs SET byte_size, checksum` in
        # SyntheticVideoMedia::Generator#patch_metadata! — so every other table,
        # including the full active_storage_attachments, must match the parent.
        UNRELATED_TABLES = %w[
          users profiles brand_memberships profile_videos photos
          active_storage_attachments active_storage_variant_records
          likes matches messages blocks reports profile_views credentials
        ].freeze

        # Full set — checked against the manifest JSON (which must never carry a
        # URL, endpoint or credential).
        MANIFEST_FORBIDDEN_TOKENS = [
          "r2.cloudflarestorage.com", "cloudflarestorage", "https://", "http://",
          "AKIA", "aws_secret", "X-Amz-Signature", "Authorization:"
        ].freeze
        # Reduced set for binary media bytes — a bare "http://" (7 bytes) can
        # appear by chance in a compressed H.264/AAC stream, so only the specific
        # endpoint / credential identifiers are meaningful there.
        MEDIA_FORBIDDEN_TOKENS = [
          "r2.cloudflarestorage.com", "cloudflarestorage",
          "AKIA", "aws_secret", "X-Amz-Signature"
        ].freeze

        def initialize(media_v3_connection:, parent_connection:, corpus_dir:, manifest:,
          second_corpus_dir: nil, expected_object_count: EXPECTED_AUTHORIZED_COUNT)
          @v3 = media_v3_connection
          @parent = parent_connection
          @corpus_dir = File.expand_path(corpus_dir)
          @manifest = manifest
          @second_corpus_dir = second_corpus_dir && File.expand_path(second_corpus_dir)
          @expected_object_count = expected_object_count
          @checks = []
        end

        def call
          objects = @manifest.fetch("objects")
          by_blob = objects.to_h { |o| [ o.fetch("source_blob_id").to_s, o ] }
          v3_rows = @v3.exec_query(VIDEO_STRUCT_SQL).to_a.map { |r| r.transform_keys(&:to_s) }
          parent_rows = @parent.exec_query(VIDEO_STRUCT_SQL).to_a.map { |r| r.transform_keys(&:to_s) }

          v3_blob_ids = v3_rows.map { |r| r.fetch("blob_id").to_s }.uniq.sort
          manifest_blob_ids = by_blob.keys.sort

          check("01_every_required_attachment_resolves",
            (v3_blob_ids - manifest_blob_ids).empty? && v3_rows.all? { |r| by_blob.key?(r.fetch("blob_id").to_s) },
            "unresolved=#{(v3_blob_ids - manifest_blob_ids).size}")
          check("02_no_unexpected_objects",
            (manifest_blob_ids - v3_blob_ids).empty? && manifest_blob_ids.size == v3_blob_ids.size,
            "extra=#{(manifest_blob_ids - v3_blob_ids).size}")

          authorized_ids = @v3.exec_query(AUTHORIZED_BLOB_IDS_SQL).to_a.map { |r| r.fetch("blob_id").to_s }

          verify_manifest_keys_safe(objects)
          verify_bytes(objects)
          verify_media(objects)
          verify_no_structural_drift(v3_rows, parent_rows, by_blob)
          verify_manifest_binds_to_db(objects, authorized_ids)
          verify_complete_blob_table_drift(authorized_ids)
          verify_attachments_table_unchanged
          verify_unrelated_tables_unchanged
          verify_no_production_leakage
          verify_determinism(objects)

          Result.new(ok: @checks.all? { |c| c[:ok] }, checks: @checks, object_count: objects.size)
        end

        private

        def objects_root = File.join(@corpus_dir, "objects")

        # Review Finding 3: never build a filesystem path from an unvalidated
        # manifest source_key. Returns an absolute path PROVEN strictly inside
        # the corpus objects root, or nil (unsafe key / symlink escape / absent).
        def object_path(o)
          Date9ja::Storage::SafeObjectKey.resolve_within(objects_root, o.fetch("source_key"))
        end

        # Every manifest source_key must satisfy the shared opaque-object-key
        # grammar (no absolute path, no "..", no backslash/control/whitespace/
        # %#?), and must not resolve through a symlink out of the corpus root —
        # checked BEFORE any file is read.
        def verify_manifest_keys_safe(objects)
          bad_grammar = escapes = 0
          objects.each do |o|
            key = o.fetch("source_key")
            if Date9ja::Storage::SafeObjectKey.valid?(key)
              # a well-formed key that still resolves outside root (symlinked
              # ancestor) or to a non-file is an escape, not merely "missing".
              resolved = Date9ja::Storage::SafeObjectKey.resolve_within(objects_root, key)
              escapes += 1 if resolved.nil? && File.exist?(File.join(objects_root, key))
            else
              bad_grammar += 1
            end
          end
          check("24_manifest_keys_are_safe", bad_grammar.zero? && escapes.zero?,
            "bad_grammar=#{bad_grammar} path_escapes=#{escapes}")
        end

        def verify_bytes(objects)
          missing = bounded = checksum_bad = size_bad = re_render_bad = 0

          objects.each do |o|
            path = object_path(o)
            unless path && File.file?(path) && File.ftype(path) == "file"
              missing += 1 # unsafe key / escape / absent / non-file
              next
            end
            bytes = File.binread(path)
            bounded += 1 if bytes.bytesize > BYTE_CEILING
            size_bad += 1 unless bytes.bytesize == o.fetch("byte_size")
            checksum_bad += 1 unless Digest::MD5.base64digest(bytes) == o.fetch("checksum")

            expected = SyntheticVideoMedia.render(
              source_blob_id: o.fetch("source_blob_id"),
              canonical_content_type: o.fetch("canonical_content_type"),
              seed: o.fetch("seed")
            )
            re_render_bad += 1 unless expected == bytes
          end

          check("03_every_object_present", missing.zero?, "missing=#{missing}")
          check("04_every_object_bounded", bounded.zero?, "oversize=#{bounded}")
          check("05_checksum_matches_bytes", checksum_bad.zero?, "mismatch=#{checksum_bad}")
          check("06_byte_size_matches_bytes", size_bad.zero?, "mismatch=#{size_bad}")
          check("13_no_production_media_bytes", re_render_bad.zero?,
            "objects that are not a byte-exact re-render of the checked-in generator=#{re_render_bad}")
        end

        # Independent inspection of the actual bytes through the shared runtime.
        def verify_media(objects)
          type_mismatch = container_invalid = probe_failed = 0
          duration_nonpositive = duration_out_of_tolerance = over_limit = 0

          objects.each do |o|
            path = object_path(o)
            next unless path && File.file?(path)

            bytes = File.binread(path)
            type_mismatch += 1 unless VIDEO_KIND.detect_type(bytes) == o.fetch("canonical_content_type")

            begin
              Media::VideoContainerValidator.call(bytes)
            rescue Media::VideoContainerValidator::Error
              container_invalid += 1
              next
            end

            begin
              probe = Media::VideoProcessor.probe(bytes)
            rescue Media::VideoProcessor::Error, Media::VideoProcessor::TimedOut
              probe_failed += 1
              next
            end

            duration = probe.duration_seconds
            if duration.nil? || duration <= 0
              duration_nonpositive += 1
              next
            end
            expected = o.fetch("expected_duration_seconds").to_f
            duration_out_of_tolerance += 1 if (duration - expected).abs > DURATION_TOLERANCE_SECONDS
            over_limit += 1 if duration > MAX_DURATION_SECONDS
          end

          check("18_detected_container_type_matches", type_mismatch.zero?, "mismatch=#{type_mismatch}")
          check("19_container_structurally_valid", container_invalid.zero?, "invalid=#{container_invalid}")
          check("20_ffprobe_succeeds", probe_failed.zero?, "failed=#{probe_failed}")
          check("21_duration_positive", duration_nonpositive.zero?, "nonpositive=#{duration_nonpositive}")
          check("22_duration_within_expected_tolerance", duration_out_of_tolerance.zero?,
            "out_of_tolerance=#{duration_out_of_tolerance} tolerance_s=#{DURATION_TOLERANCE_SECONDS}")
          check("23_happy_path_duration_within_brand_limit", over_limit.zero?,
            "over_#{MAX_DURATION_SECONDS}s=#{over_limit}")
        end

        def verify_no_structural_drift(v3_rows, parent_rows, by_blob)
          identity = lambda do |rows|
            rows.map do |r|
              [ r["video_id"], r["user_id"], r["moderation_status"],
                r["attachment_id"], r["blob_id"], r["key"], r["content_type"], r["service_name"] ].map(&:to_s)
            end
          end
          check("09_no_source_identity_drift", identity.call(v3_rows) == identity.call(parent_rows),
            "rows_v3=#{v3_rows.size} rows_parent=#{parent_rows.size}")

          graph = ->(rows) { rows.map { |r| [ r["attachment_id"], r["blob_id"], r["key"] ].map(&:to_s) }.sort }
          check("10_attachment_blob_graph_identical", graph.call(v3_rows) == graph.call(parent_rows), "")

          ownership = ->(rows) { rows.map { |r| [ r["video_id"], r["user_id"] ].map(&:to_s) }.sort }
          check("11_video_ownership_identical", ownership.call(v3_rows) == ownership.call(parent_rows), "")

          plan = ->(rows) { rows.map { |r| [ r["video_id"], r["moderation_status"] ].map(&:to_s) }.sort }
          check("12_moderation_identical", plan.call(v3_rows) == plan.call(parent_rows), "")

          drift_only_integrity =
            parent_rows.zip(v3_rows).all? do |pr, vr|
              pr && vr && pr["blob_id"] == vr["blob_id"] && by_blob.key?(vr["blob_id"].to_s) &&
                pr["content_type"] == vr["content_type"] && pr["key"] == vr["key"]
            end
          check("09b_only_integrity_metadata_rewritten", drift_only_integrity, "")
        end

        def verify_manifest_binds_to_db(objects, authorized_ids)
          authorized = authorized_ids.to_set
          db_rows = @v3.exec_query(
            "SELECT id, key, service_name, content_type, byte_size, checksum " \
            "FROM active_storage_blobs WHERE id IN (#{sql_int_list(authorized_ids)}) ORDER BY id"
          ).to_a.to_h { |r| [ r.fetch("id").to_s, r.transform_keys(&:to_s) ] }

          by_id = Hash.new { |h, k| h[k] = [] }
          objects.each { |o| by_id[o.fetch("source_blob_id").to_s] << o }

          duplicate_ids = by_id.count { |_, v| v.size > 1 }
          unexpected = by_id.keys.count { |id| !authorized.include?(id) }
          missing = 0
          field_mismatch = Hash.new(0)

          authorized_ids.each do |id|
            entries = by_id[id]
            if entries.size != 1
              missing += 1 if entries.empty?
              next
            end
            o = entries.first
            row = db_rows[id]
            next if row.nil?

            field_mismatch[:source_key]   += 1 unless o["source_key"] == row["key"]
            field_mismatch[:service_name] += 1 unless o["service_name"] == row["service_name"]
            field_mismatch[:content_type] += 1 unless o["canonical_content_type"] == row["content_type"]
            manifest_bytes = canonical_byte_size(o["byte_size"])
            field_mismatch[:byte_size] += 1 unless manifest_bytes && manifest_bytes == Integer(row["byte_size"])
            field_mismatch[:checksum]     += 1 unless o["checksum"] == row["checksum"]
          end

          ok = duplicate_ids.zero? && unexpected.zero? && missing.zero? &&
            field_mismatch.values.all?(&:zero?) && objects.size == authorized_ids.size

          check("16_manifest_rows_match_media_v3_blobs", ok,
            "authorized=#{authorized_ids.size} manifest=#{objects.size} missing=#{missing} " \
            "duplicate_source_blob_id=#{duplicate_ids} unexpected=#{unexpected} " \
            "field_mismatch=#{field_mismatch.select { |_, n| n.positive? }}")
        end

        def canonical_byte_size(value)
          return nil unless value.instance_of?(Integer)
          return nil if value.negative?

          value
        end

        def db_value_equal?(a, b)
          return true if a.nil? && b.nil?
          return false if a.nil? || b.nil?

          a == b && a.class == b.class
        end

        def verify_complete_blob_table_drift(authorized_ids)
          columns = @v3.exec_query(BLOB_COLUMNS_SQL).to_a.map { |r| r.fetch("column_name") }
          select = columns.map { |c| %("#{c}") }.join(", ")
          v3 = @v3.exec_query("SELECT #{select} FROM active_storage_blobs ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }
          parent = @parent.exec_query("SELECT #{select} FROM active_storage_blobs ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }

          authorized = authorized_ids.to_set
          same_count = v3.size == parent.size
          same_ids = v3.keys.sort == parent.keys.sort
          inserted = (v3.keys - parent.keys).size
          deleted  = (parent.keys - v3.keys).size

          unauthorized_change = wrong_column_change = authorized_actually_changed = 0

          (v3.keys & parent.keys).each do |id|
            differing = columns.reject { |c| db_value_equal?(v3[id][c], parent[id][c]) }
            next if differing.empty? && !authorized.include?(id)

            if authorized.include?(id)
              wrong_column_change += 1 unless (differing - MUTABLE_COLUMNS).empty?
              authorized_actually_changed += 1 unless differing.empty?
            elsif differing.any?
              unauthorized_change += 1
            end
          end

          ok = same_count && same_ids && inserted.zero? && deleted.zero? &&
            unauthorized_change.zero? && wrong_column_change.zero? &&
            authorized_ids.size == @expected_object_count

          check("17_complete_blob_table_drift_is_authorized", ok,
            "columns=#{columns.size} rows_v3=#{v3.size} rows_parent=#{parent.size} " \
            "inserted=#{inserted} deleted=#{deleted} authorized=#{authorized_ids.size} " \
            "authorized_changed=#{authorized_actually_changed} " \
            "wrong_column_change=#{wrong_column_change} non_video_change=#{unauthorized_change}")
        end

        def sql_int_list(ids)
          safe = ids.map { |i| Integer(i) }
          safe.empty? ? "NULL" : safe.join(", ")
        end

        # Review Finding 2: the full active_storage_attachments table must be
        # byte-identical to the parent (the generator only writes
        # active_storage_blobs.byte_size/checksum — it never touches attachments).
        def verify_attachments_table_unchanged
          columns = @v3.exec_query(ATTACHMENT_COLUMNS_SQL).to_a.map { |r| r.fetch("column_name") }
          select = columns.map { |c| %("#{c}") }.join(", ")
          v3 = @v3.exec_query("SELECT #{select} FROM active_storage_attachments ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }
          parent = @parent.exec_query("SELECT #{select} FROM active_storage_attachments ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }

          inserted = (v3.keys - parent.keys).size
          deleted  = (parent.keys - v3.keys).size
          changed = (v3.keys & parent.keys).count do |id|
            columns.any? { |c| !db_value_equal?(v3[id][c], parent[id][c]) }
          end

          check("27_attachments_table_unchanged",
            v3.size == parent.size && inserted.zero? && deleted.zero? && changed.zero?,
            "columns=#{columns.size} rows_v3=#{v3.size} rows_parent=#{parent.size} " \
            "inserted=#{inserted} deleted=#{deleted} changed=#{changed}")
        end

        # Review Finding 2: unrelated tables' row counts must match the parent.
        # The generator's only write statement is the blob metadata UPDATE.
        def verify_unrelated_tables_unchanged
          mismatches = []
          checked = 0
          UNRELATED_TABLES.each do |table|
            next unless table_exists?(@v3, table) && table_exists?(@parent, table)

            checked += 1
            v3_count = table_count(@v3, table)
            parent_count = table_count(@parent, table)
            mismatches << "#{table}(#{parent_count}->#{v3_count})" unless v3_count == parent_count
          end
          check("28_unrelated_table_row_counts_unchanged", mismatches.empty? && checked.positive?,
            "checked=#{checked} mismatches=#{mismatches.join(',')}")
        end

        def table_exists?(conn, table)
          conn.exec_query(
            "SELECT to_regclass(#{conn.quote("public.#{table}")}) AS t"
          ).to_a.first&.fetch("t", nil).present?
        rescue StandardError
          false
        end

        def table_count(conn, table)
          # `table` is from the fixed UNRELATED_TABLES allowlist only.
          conn.exec_query("SELECT COUNT(*) AS n FROM #{table}").to_a.first.fetch("n").to_i
        end

        def verify_no_production_leakage
          offenders = 0
          manifest_json = JSON.generate(@manifest)
          offenders += 1 if MANIFEST_FORBIDDEN_TOKENS.any? { |t| manifest_json.include?(t) }

          Dir.glob(File.join(@corpus_dir, "**", "*")).each do |path|
            next unless File.file?(path)

            tokens = path.end_with?("manifest.json", "manifest.fingerprint") ? MANIFEST_FORBIDDEN_TOKENS : MEDIA_FORBIDDEN_TOKENS
            bytes = File.binread(path) # whole file — a leaked endpoint can sit anywhere
            offenders += 1 if tokens.any? { |t| bytes.include?(t) }
          end
          check("14_no_production_endpoint_or_credential", offenders.zero?, "offenders=#{offenders}")
        end

        def verify_determinism(objects)
          fingerprint = Generator.fingerprint_of(@manifest)
          if @second_corpus_dir && File.file?(File.join(@second_corpus_dir, "manifest.json"))
            second = JSON.parse(File.read(File.join(@second_corpus_dir, "manifest.json")))
            same_fp = Generator.fingerprint_of(second) == fingerprint
            same_bytes = objects.all? do |o|
              a = object_path(o)
              b = Date9ja::Storage::SafeObjectKey.resolve_within(File.join(@second_corpus_dir, "objects"), o.fetch("source_key"))
              a && b && File.binread(a) == File.binread(b)
            end
            check("15_generator_is_deterministic", same_fp && same_bytes,
              "fingerprint_match=#{same_fp} bytes_match=#{same_bytes}")
          else
            in_memory_ok = objects.all? do |o|
              path = object_path(o)
              next false unless path && File.file?(path)

              File.binread(path) == SyntheticVideoMedia.render(
                source_blob_id: o.fetch("source_blob_id"),
                canonical_content_type: o.fetch("canonical_content_type"),
                seed: o.fetch("seed")
              )
            end
            check("15_generator_is_deterministic", in_memory_ok,
              "in_memory_re_render_matches=#{in_memory_ok} (no second corpus supplied)")
          end
        end

        def check(id, ok, detail)
          @checks << { check: id, ok: !!ok, detail: detail.to_s }
        end
      end
    end
  end
end
