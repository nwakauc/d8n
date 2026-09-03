# frozen_string_literal: true

module Date9ja
  module Snapshot
    module SyntheticMedia
      # Fail-closed pre-flight for the synthetic corpus. Proves the 15 checks in
      # MEDIA-TRANSFER.md §21 L2 before any Pass 2 rehearsal touches it. Output is
      # PII-free: check ids, counts, and structural mismatch shapes only — never a
      # storage key, checksum value, or row payload.
      #
      #   Verifier.new(media_v2_connection: c1, parent_connection: c2,
      #                corpus_dir: dir, manifest:).call
      class Verifier
        Result = Data.define(:ok, :checks, :object_count) do
          def ok? = ok
          def failures = checks.reject { |c| c[:ok] }
        end

        PHOTO_STRUCT_SQL = <<~SQL
          SELECT p.id AS photo_id, p.user_id, p.position, p.moderation_status, p.is_primary::int AS is_primary,
                 a.id AS attachment_id, a.blob_id,
                 b.key, b.content_type, b.service_name
          FROM photos p
          JOIN active_storage_attachments a
            ON a.record_type = '#{PHOTO_RECORD_TYPE}' AND a.name = '#{PHOTO_ATTACHMENT_NAME}' AND a.record_id = p.id
          JOIN active_storage_blobs b ON b.id = a.blob_id
          ORDER BY p.id, a.id
        SQL

        # The authoritative set of blob rows the media_v2 generator is allowed to
        # have mutated — derived from the Photo image attachment graph, NOT from
        # the manifest.
        AUTHORIZED_BLOB_IDS_SQL = <<~SQL
          SELECT a.blob_id
          FROM active_storage_attachments a
          WHERE a.record_type = '#{PHOTO_RECORD_TYPE}' AND a.name = '#{PHOTO_ATTACHMENT_NAME}'
          ORDER BY a.blob_id
        SQL

        BLOB_COLUMNS_SQL = <<~SQL
          SELECT column_name
          FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'active_storage_blobs'
          ORDER BY ordinal_position
        SQL

        # Only these two columns may differ between the parent artifact and
        # media_v2, and only on the authorized Photo blob rows.
        MUTABLE_COLUMNS = %w[byte_size checksum].freeze
        EXPECTED_AUTHORIZED_COUNT = 279

        FORBIDDEN_TOKENS = [
          "r2.cloudflarestorage.com", "cloudflarestorage", "https://", "http://",
          "AKIA", "aws_secret", "X-Amz-Signature", "Authorization:"
        ].freeze

        def initialize(media_v2_connection:, parent_connection:, corpus_dir:, manifest:,
          second_corpus_dir: nil, image_processor: Media::ImageProcessor,
          expected_object_count: EXPECTED_AUTHORIZED_COUNT)
          @v2 = media_v2_connection
          @parent = parent_connection
          @corpus_dir = File.expand_path(corpus_dir)
          @manifest = manifest
          @second_corpus_dir = second_corpus_dir && File.expand_path(second_corpus_dir)
          @image_processor = image_processor
          @expected_object_count = expected_object_count
          @checks = []
        end

        def call
          objects = @manifest.fetch("objects")
          by_blob = objects.to_h { |o| [ o.fetch("source_blob_id").to_s, o ] }
          v2_rows = @v2.exec_query(PHOTO_STRUCT_SQL).to_a.map { |r| r.transform_keys(&:to_s) }
          parent_rows = @parent.exec_query(PHOTO_STRUCT_SQL).to_a.map { |r| r.transform_keys(&:to_s) }

          v2_blob_ids = v2_rows.map { |r| r.fetch("blob_id").to_s }.uniq.sort
          manifest_blob_ids = by_blob.keys.sort

          check("01_every_required_attachment_resolves",
            (v2_blob_ids - manifest_blob_ids).empty? && v2_rows.all? { |r| by_blob.key?(r.fetch("blob_id").to_s) },
            "unresolved=#{(v2_blob_ids - manifest_blob_ids).size}")

          check("02_no_unexpected_objects",
            (manifest_blob_ids - v2_blob_ids).empty? && manifest_blob_ids.size == v2_blob_ids.size,
            "extra=#{(manifest_blob_ids - v2_blob_ids).size}")

          authorized_ids = @v2.exec_query(AUTHORIZED_BLOB_IDS_SQL).to_a
            .map { |r| r.fetch("blob_id").to_s }

          verify_bytes(objects)
          verify_no_structural_drift(v2_rows, parent_rows, by_blob)
          verify_manifest_binds_to_db(objects, authorized_ids)
          verify_complete_blob_table_drift(authorized_ids)
          verify_no_production_leakage
          verify_determinism(objects)

          Result.new(ok: @checks.all? { |c| c[:ok] }, checks: @checks, object_count: objects.size)
        end

        private

        def verify_bytes(objects)
          missing = bounded = ct_mismatch = 0
          checksum_bad = size_bad = undecodable = 0
          re_render_bad = 0

          objects.each do |o|
            path = File.join(@corpus_dir, "objects", o.fetch("source_key"))
            unless File.file?(path)
              missing += 1
              next
            end
            bytes = File.binread(path)
            bounded += 1 if bytes.bytesize > BYTE_CEILING
            size_bad += 1 unless bytes.bytesize == o.fetch("byte_size")
            checksum_bad += 1 unless Digest::MD5.base64digest(bytes) == o.fetch("checksum")

            detected = Profiles::PhotoUpload.detect_image_type(bytes[0, 16])
            ct_mismatch += 1 unless detected == o.fetch("canonical_content_type")

            begin
              @image_processor.call(bytes)
            rescue Media::ImageProcessor::Error
              undecodable += 1
            end

            expected = SyntheticMedia.render(
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
          check("07_detected_content_type_matches", ct_mismatch.zero?, "mismatch=#{ct_mismatch}")
          check("08_decodes_through_processor", undecodable.zero?, "undecodable=#{undecodable}")
          check("13_no_production_media_bytes", re_render_bad.zero?,
            "objects that are not a byte-exact re-render of the checked-in generator=#{re_render_bad}")
        end

        def verify_no_structural_drift(v2_rows, parent_rows, by_blob)
          identity = lambda do |rows|
            rows.map do |r|
              [ r["photo_id"], r["user_id"], r["position"], r["moderation_status"], r["is_primary"],
                r["attachment_id"], r["blob_id"], r["key"], r["content_type"], r["service_name"] ].map(&:to_s)
            end
          end
          check("09_no_source_identity_drift", identity.call(v2_rows) == identity.call(parent_rows),
            "rows_v2=#{v2_rows.size} rows_parent=#{parent_rows.size}")

          graph = ->(rows) { rows.map { |r| [ r["attachment_id"], r["blob_id"], r["key"] ].map(&:to_s) }.sort }
          check("10_attachment_blob_graph_identical", graph.call(v2_rows) == graph.call(parent_rows), "")

          ownership = ->(rows) { rows.map { |r| [ r["photo_id"], r["user_id"] ].map(&:to_s) }.sort }
          check("11_photo_ownership_identical", ownership.call(v2_rows) == ownership.call(parent_rows), "")

          plan = ->(rows) { rows.map { |r| [ r["photo_id"], r["position"], r["moderation_status"], r["is_primary"] ].map(&:to_s) }.sort }
          check("12_moderation_primary_order_identical", plan.call(v2_rows) == plan.call(parent_rows), "")

          # Only byte_size / checksum may differ between parent and media_v2.
          drift_only_integrity =
            parent_rows.zip(v2_rows).all? do |pr, vr|
              pr["blob_id"] == vr["blob_id"] &&
                by_blob.key?(vr["blob_id"].to_s) &&
                pr["content_type"] == vr["content_type"] &&
                pr["key"] == vr["key"]
            end
          check("09b_only_integrity_metadata_rewritten", drift_only_integrity, "")
        end

        # FIX 2 — every manifest object is bound, field-for-field, to the
        # authoritative media_v2 blob row it claims to describe. The manifest does
        # not get to define the authorized set; the Photo attachment graph does.
        def verify_manifest_binds_to_db(objects, authorized_ids)
          authorized = authorized_ids.to_set
          db_rows = @v2.exec_query(
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

            # FIX 1 — exact byte_size typing. The manifest contract is: byte_size
            # is a JSON integer. Reject anything else (float, "123junk", " 123",
            # "123.0", nil, boolean, negative) rather than coercing it — a
            # permissive .to_i lets malformed text compare equal to the DB int.
            manifest_bytes = canonical_byte_size(o["byte_size"])
            field_mismatch[:byte_size] += 1 unless manifest_bytes && manifest_bytes == Integer(row["byte_size"])

            field_mismatch[:checksum]     += 1 unless o["checksum"] == row["checksum"]
          end

          ok = duplicate_ids.zero? && unexpected.zero? && missing.zero? &&
            field_mismatch.values.all?(&:zero?) &&
            objects.size == authorized_ids.size

          check("16_manifest_rows_match_media_v2_blobs", ok,
            "authorized=#{authorized_ids.size} manifest=#{objects.size} missing=#{missing} " \
            "duplicate_source_blob_id=#{duplicate_ids} unexpected=#{unexpected} " \
            "field_mismatch=#{field_mismatch.select { |_, n| n.positive? }}")
        end

        # Manifest byte_size must be a canonical non-negative JSON integer.
        # Returns the Integer on success, nil on any malformed / wrong-typed
        # value. No silent normalization.
        def canonical_byte_size(value)
          return nil unless value.instance_of?(Integer)
          return nil if value.negative?

          value
        end

        # Null-safe, type-preserving equality for the schema-driven blob-table
        # drift comparison. NULL and '' are distinct; 0, false, '' are distinct.
        def db_value_equal?(a, b)
          return true if a.nil? && b.nil?
          return false if a.nil? || b.nil?

          a == b && a.class == b.class
        end

        # FIX 3 — schema-driven full-table proof that media_v2 changed ONLY
        # byte_size/checksum and ONLY on the 279 authorized Photo blob rows,
        # across every active_storage_blobs row and every column.
        def verify_complete_blob_table_drift(authorized_ids)
          columns = @v2.exec_query(BLOB_COLUMNS_SQL).to_a.map { |r| r.fetch("column_name") }
          select = columns.map { |c| %("#{c}") }.join(", ")
          # to_a WITHOUT stringifying values — keep native Ruby types (nil stays
          # nil, Integer stays Integer, Time stays Time) so db_value_equal? can
          # tell SQL NULL from '' and 0 from false.
          v2 = @v2.exec_query("SELECT #{select} FROM active_storage_blobs ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }
          parent = @parent.exec_query("SELECT #{select} FROM active_storage_blobs ORDER BY id").to_a
            .to_h { |r| [ r.fetch("id").to_s, r ] }

          authorized = authorized_ids.to_set
          same_count = v2.size == parent.size
          same_ids = v2.keys.sort == parent.keys.sort
          inserted = (v2.keys - parent.keys).size
          deleted  = (parent.keys - v2.keys).size

          unauthorized_change = 0        # any change on a non-Photo blob
          wrong_column_change = 0        # a Photo blob column other than byte_size/checksum changed
          authorized_actually_changed = 0

          (v2.keys & parent.keys).each do |id|
            vr = v2[id]
            pr = parent[id]
            differing = columns.reject { |c| db_value_equal?(vr[c], pr[c]) }
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
            "columns=#{columns.size} rows_v2=#{v2.size} rows_parent=#{parent.size} " \
            "inserted=#{inserted} deleted=#{deleted} authorized=#{authorized_ids.size} " \
            "authorized_changed=#{authorized_actually_changed} " \
            "wrong_column_change=#{wrong_column_change} non_photo_change=#{unauthorized_change}")
        end

        def sql_int_list(ids)
          safe = ids.map { |i| Integer(i) }
          safe.empty? ? "NULL" : safe.join(", ")
        end

        def verify_no_production_leakage
          offenders = 0
          manifest_json = JSON.generate(@manifest)
          offenders += 1 if FORBIDDEN_TOKENS.any? { |t| manifest_json.include?(t) }
          Dir.glob(File.join(@corpus_dir, "**", "*")).each do |path|
            next unless File.file?(path)

            head = File.binread(path, 4_096)
            offenders += 1 if FORBIDDEN_TOKENS.any? { |t| head.include?(t) }
          end
          check("14_no_production_endpoint_or_credential", offenders.zero?, "offenders=#{offenders}")
        end

        def verify_determinism(objects)
          fingerprint = Generator.fingerprint_of(@manifest)
          if @second_corpus_dir && File.file?(File.join(@second_corpus_dir, "manifest.json"))
            second = JSON.parse(File.read(File.join(@second_corpus_dir, "manifest.json")))
            same_fingerprint = Generator.fingerprint_of(second) == fingerprint
            same_bytes = objects.all? do |o|
              a = File.join(@corpus_dir, "objects", o.fetch("source_key"))
              b = File.join(@second_corpus_dir, "objects", o.fetch("source_key"))
              File.file?(a) && File.file?(b) && File.binread(a) == File.binread(b)
            end
            check("15_generator_is_deterministic", same_fingerprint && same_bytes,
              "fingerprint_match=#{same_fingerprint} bytes_match=#{same_bytes}")
          else
            # No second corpus supplied: re-render every object in memory and
            # compare against the stored file + manifest fingerprint.
            in_memory_ok = objects.all? do |o|
              path = File.join(@corpus_dir, "objects", o.fetch("source_key"))
              next false unless File.file?(path)

              File.binread(path) == SyntheticMedia.render(
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
