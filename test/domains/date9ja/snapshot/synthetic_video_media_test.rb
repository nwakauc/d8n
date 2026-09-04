# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    module SyntheticVideoMedia
      # In-memory stand-in for the media_v3 / parent snapshot connections. Models
      # a tiny active_storage_blobs table + the ProfileVideo `video` attachment
      # graph so the generator/verifier queries resolve. Mirrors the photo
      # SyntheticMedia FakeConn.
      class FakeConn
        BLOB_COLUMNS = %w[id key filename content_type metadata service_name byte_size checksum created_at].freeze
        ATTACHMENT_COLUMNS = %w[id name record_type record_id blob_id created_at].freeze

        def initialize(blobs:, video_struct: nil, attachments: nil, table_counts: nil)
          @blobs = blobs.map { |b| normalize(b) }
          @src = blobs
          @video_struct = video_struct
          @attachments = attachments || default_attachments
          @table_counts = table_counts || { "users" => 3, "profiles" => 3, "profile_videos" => video_blobs.size }
        end

        attr_reader :blobs, :attachments

        def add_row!(hash) = @blobs << normalize(hash)

        def normalize(b)
          BLOB_COLUMNS.to_h { |c| [ c, b.fetch(c, default_for(c, b)) ] }.merge("_non_video" => b["_non_video"])
        end

        def exec_query(sql, *)
          rows =
            if sql.include?("information_schema.columns") && sql.include?("active_storage_attachments")
              ATTACHMENT_COLUMNS.map { |c| { "column_name" => c } }
            elsif sql.include?("information_schema.columns")
              BLOB_COLUMNS.map { |c| { "column_name" => c } }
            elsif sql.include?("to_regclass")
              t = sql[/public\.([a-z_]+)/, 1]
              [ { "t" => (@table_counts.key?(t) ? t : nil) } ]
            elsif sql.include?("SELECT COUNT(*) AS n FROM ")
              t = sql[/FROM (\w+)/, 1]
              [ { "n" => @table_counts.fetch(t, 0) } ]
            elsif sql.include?("FROM profile_videos")
              @video_struct || default_video_struct
            elsif sql.include?("FROM active_storage_attachments") && sql.include?("WHERE a.record_type")
              video_blobs.map { |b| { "blob_id" => b["id"] } }
            elsif sql.include?("FROM active_storage_attachments") && !sql.include?("JOIN")
              @attachments
            elsif sql.include?("FROM active_storage_blobs") && sql.include?("WHERE id IN")
              ids = sql[/WHERE id IN \(([^)]*)\)/, 1].split(",").map(&:strip)
              @blobs.select { |b| ids.include?(b["id"].to_s) }
                .map { |b| b.slice("id", "key", "service_name", "content_type", "byte_size", "checksum") }
            elsif sql.include?("FROM active_storage_blobs") && !sql.include?("JOIN")
              @blobs.map { |b| b.slice(*BLOB_COLUMNS) }
            else
              video_blobs.map { |b| b.slice("id", "key", "content_type", "service_name") }
            end
          FakeResult.new(rows)
        end

        def default_attachments
          video_blobs.each_with_index.map do |b, i|
            ATTACHMENT_COLUMNS.to_h do |c|
              [ c, { "id" => (500 + i).to_s, "name" => "video", "record_type" => "ProfileVideo",
                     "record_id" => (i + 1).to_s, "blob_id" => b["id"], "created_at" => "2024-01-01 00:00:00" }[c] ]
            end
          end
        end

        def exec_update(sql, *)
          id = sql[/WHERE id = (\d+)/, 1].to_i
          size = sql[/byte_size = (\d+)/, 1].to_i
          checksum = sql[/checksum = '([^']+)'/, 1]
          [ @blobs, @src ].each do |set|
            row = set.find { |b| b["id"].to_i == id }
            next unless row

            row["byte_size"] = size
            row["checksum"] = checksum
          end
          1
        end

        def transaction = yield
        def quote(value) = "'#{value}'"

        private

        FakeResult = Struct.new(:to_a)

        def video_blobs = @blobs.reject { |b| b["_non_video"] }

        def default_for(col, blob)
          case col
          when "filename" then "video-#{blob['id']}.mp4"
          when "metadata" then "{}"
          when "created_at" then "2024-01-01 00:00:00"
          when "byte_size" then 0
          when "checksum" then ""
          end
        end

        def default_video_struct
          video_blobs.each_with_index.map do |b, i|
            {
              "video_id" => (i + 1).to_s, "user_id" => (100 + i).to_s, "moderation_status" => "0",
              "attachment_id" => (500 + i).to_s, "blob_id" => b["id"],
              "key" => b["key"], "content_type" => b["content_type"], "service_name" => b["service_name"]
            }
          end
        end
      end

      class GeneratorTest < ActiveSupport::TestCase
        setup do
          @dir = Dir.mktmpdir("svm-gen")
          @blobs = [
            { "id" => "1", "key" => "snapshot/1/aaa", "content_type" => "video/mp4", "service_name" => "cloudflare", "byte_size" => 1, "checksum" => "old1" },
            { "id" => "2", "key" => "snapshot/2/bbb", "content_type" => "video/quicktime", "service_name" => "cloudflare", "byte_size" => 1, "checksum" => "old2" },
            { "id" => "3", "key" => "snapshot/3/ccc", "content_type" => "video/mp4", "service_name" => "cloudflare", "byte_size" => 1, "checksum" => "old3" }
          ]
          @conn = FakeConn.new(blobs: @blobs)
        end

        teardown { FileUtils.remove_entry(@dir) }

        test "renders one structurally valid video per blob with a fingerprinted manifest" do
          result = Generator.new(connection: @conn, corpus_dir: @dir, seed: "t").call

          assert_equal 3, result.object_count
          assert_equal({ "video/mp4" => 2, "video/quicktime" => 1 }, result.content_type_counts)

          manifest = JSON.parse(File.read(result.manifest_path))
          assert_equal Generator.fingerprint_of(manifest), result.manifest_fingerprint
          assert_equal "date9ja_snapshot_sanitized_media_v3", manifest["artifact"]
          assert_includes manifest["evidence_rule"], "proves NOTHING about the real videos"

          manifest["objects"].each do |o|
            bytes = File.binread(File.join(@dir, "objects", o["source_key"]))
            assert_equal bytes.bytesize, o["byte_size"]
            assert_equal Digest::MD5.base64digest(bytes), o["checksum"]
            assert_equal o["canonical_content_type"],
              Migration::MediaTransfer::MediaKind::Video.detect_type(bytes)
            assert_nothing_raised { Media::VideoContainerValidator.call(bytes) }
            probe = Media::VideoProcessor.probe(bytes)
            assert_operator probe.duration_seconds, :>, 0
            assert_in_delta o["expected_duration_seconds"], probe.duration_seconds, 0.75
            assert_operator probe.duration_seconds, :<=, 60
          end
        end

        test "rewrites only byte_size and checksum on the media_v3 blob rows" do
          Generator.new(connection: @conn, corpus_dir: @dir, seed: "t").call
          @blobs.each do |b|
            refute_equal "old#{b['id']}", b["checksum"]
            assert_operator b["byte_size"], :>, 100
            assert_equal "cloudflare", b["service_name"]
            assert b["key"].start_with?("snapshot/")
          end
        end

        test "is byte-for-byte deterministic across two clean runs into separate dirs" do
          r1 = Generator.new(connection: @conn, corpus_dir: @dir, seed: "t", patch_metadata: false).call
          other = Dir.mktmpdir("svm-gen-2")
          r2 = Generator.new(connection: FakeConn.new(blobs: Marshal.load(Marshal.dump(@blobs))),
            corpus_dir: other, seed: "t", patch_metadata: false).call

          assert_equal r1.manifest_fingerprint, r2.manifest_fingerprint
          Dir.glob(File.join(@dir, "objects", "**", "*")).select { |f| File.file?(f) }.each do |f|
            rel = f.delete_prefix("#{@dir}/")
            assert_equal File.binread(f), File.binread(File.join(other, rel)), "#{rel} differs across runs"
          end
        ensure
          FileUtils.remove_entry(other) if other
        end

        test "rejects an unsafe source key and writes nothing" do
          bad = FakeConn.new(blobs: [ { "id" => "1", "key" => "a/../evil", "content_type" => "video/mp4",
            "service_name" => "cloudflare", "byte_size" => 0, "checksum" => "" } ])
          assert_raises(Date9ja::Storage::SafeObjectKey::InvalidKey) do
            Generator.new(connection: bad, corpus_dir: @dir, seed: "p", patch_metadata: false).call
          end
          assert_empty Dir.glob(File.join(@dir, "objects", "**", "*")).select { |f| File.file?(f) }
        end
      end

      class VerifierTest < ActiveSupport::TestCase
        setup do
          @dir = Dir.mktmpdir("svm-ver")
          @blobs = [
            { "id" => "1", "key" => "snapshot/1/aaa", "content_type" => "video/mp4", "service_name" => "cloudflare", "byte_size" => 0, "checksum" => "" },
            { "id" => "2", "key" => "snapshot/2/bbb", "content_type" => "video/quicktime", "service_name" => "cloudflare", "byte_size" => 0, "checksum" => "" }
          ]
          @parent_blobs = Marshal.load(Marshal.dump(@blobs))
          @conn = FakeConn.new(blobs: @blobs, video_struct: video_struct(@blobs))
          Generator.new(connection: @conn, corpus_dir: @dir, seed: "v").call
          @manifest = JSON.parse(File.read(File.join(@dir, "manifest.json")))
        end

        teardown { FileUtils.remove_entry(@dir) }

        def video_struct(blobs)
          blobs.reject { |b| b["_non_video"] }.each_with_index.map do |b, i|
            { "video_id" => (i + 1).to_s, "user_id" => (100 + i).to_s, "moderation_status" => "0",
              "attachment_id" => (500 + i).to_s, "blob_id" => b["id"],
              "key" => b["key"], "content_type" => b["content_type"], "service_name" => b["service_name"] }
          end
        end

        def verifier(parent_blobs: @parent_blobs, expected_object_count: 2)
          parent = FakeConn.new(blobs: parent_blobs, video_struct: video_struct(parent_blobs))
          Verifier.new(media_v3_connection: @conn, parent_connection: parent,
            corpus_dir: @dir, manifest: @manifest, expected_object_count:)
        end

        test "passes every check for a well-formed corpus" do
          result = verifier.call
          assert result.ok?, result.failures.map { |c| "#{c[:check]}:#{c[:detail]}" }.join(", ")
        end

        test "fails 05/06/13 when a stored object is tampered" do
          path = File.join(@dir, "objects", @manifest["objects"].first["source_key"])
          File.binwrite(path, File.binread(path) + "tampered".b)
          failed = verifier.call.failures.map { |c| c[:check] }
          assert_includes failed, "05_checksum_matches_bytes"
          assert_includes failed, "06_byte_size_matches_bytes"
          assert_includes failed, "13_no_production_media_bytes"
        end

        test "fails 03/19/20 when a stored object is replaced with a non-video" do
          path = File.join(@dir, "objects", @manifest["objects"].first["source_key"])
          # keep byte_size/checksum consistent so only the media checks fire
          bogus = "not a video".b
          File.binwrite(path, bogus)
          @manifest["objects"].first["byte_size"] = bogus.bytesize
          @manifest["objects"].first["checksum"] = Digest::MD5.base64digest(bogus)
          failed = verifier.call.failures.map { |c| c[:check] }
          assert_includes failed, "18_detected_container_type_matches"
          assert_includes failed, "19_container_structurally_valid"
          assert_includes failed, "13_no_production_media_bytes"
        end

        test "fails 09 when media_v3 structural identity drifts from the parent" do
          drifted = Marshal.load(Marshal.dump(@blobs))
          drifted.first["content_type"] = "video/quicktime"
          failed = verifier(parent_blobs: drifted).call.failures.map { |c| c[:check] }
          assert_includes failed, "09_no_source_identity_drift"
        end

        test "fails 17 when a non-video blob row changed" do
          @conn.add_row!({ "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "v3only", "_non_video" => true })
          parent = @parent_blobs + [ { "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "parent", "_non_video" => true } ]
          check = verifier(parent_blobs: parent).call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "non_video_change=1"
        end

        test "fails 17 when a non-mutable column changed on a video blob" do
          @conn.blobs.first["filename"] = "renamed.mp4"
          check = verifier.call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "wrong_column_change=1"
        end

        test "fails 16 on a duplicate source_blob_id in the manifest" do
          @manifest["objects"] << @manifest["objects"].first.dup
          check = verifier.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v3_blobs" }
          refute check[:ok]
          assert_includes check[:detail], "duplicate_source_blob_id=1"
        end

        test "fails 23 if a happy-path body somehow exceeds the brand duration limit" do
          # replace object 1 with a genuine >60s video, keeping metadata consistent
          over = SyntheticVideoMedia.render_over_limit(seconds: 63)
          path = File.join(@dir, "objects", @manifest["objects"].first["source_key"])
          File.binwrite(path, over)
          o = @manifest["objects"].first
          o["byte_size"] = over.bytesize
          o["checksum"] = Digest::MD5.base64digest(over)
          o["expected_duration_seconds"] = 63
          failed = verifier.call.failures.map { |c| c[:check] }
          assert_includes failed, "23_happy_path_duration_within_brand_limit"
          assert_includes failed, "13_no_production_media_bytes"
        end

        test "14 flags a production endpoint token in the manifest" do
          @manifest["lineage_note"] = "see https://acct.r2.cloudflarestorage.com/bucket"
          check = verifier.call.checks.find { |c| c[:check] == "14_no_production_endpoint_or_credential" }
          refute check[:ok]
        end

        # --- Finding 3: manifest path safety --------------------------------

        {
          "absolute path"        => "/etc/passwd",
          "single ../ escape"    => "../evil",
          "nested ../../ escape" => "a/../../evil",
          "backslash traversal"  => "a\\..\\evil",
          "percent-encoded"      => "a/%2e%2e/evil",
          "whitespace"           => "a b/evil"
        }.each do |label, key|
          test "24 rejects a manifest source_key with #{label} (fail closed, no host-path read)" do
            @manifest["objects"].first["source_key"] = key
            # object_path resolves through SafeObjectKey -> nil for an unsafe key,
            # so no File.binread is ever attempted on a caller-supplied path.
            assert_nil verifier.send(:object_path, @manifest["objects"].first)

            result = verifier.call
            refute result.ok?
            assert_includes result.failures.map { |c| c[:check] }, "24_manifest_keys_are_safe"
          end
        end

        test "24 rejects a manifest key whose corpus ancestor is a symlink escaping root" do
          outside = Dir.mktmpdir("svm-outside")
          File.write(File.join(outside, "secret"), "SECRET")
          FileUtils.mkdir_p(File.join(@dir, "objects", "snapshot"))
          File.symlink(outside, File.join(@dir, "objects", "snapshot", "esc"))
          @manifest["objects"].first["source_key"] = "snapshot/esc/secret"

          result = verifier.call
          refute result.ok?
          assert_includes result.failures.map { |c| c[:check] }, "24_manifest_keys_are_safe"
        ensure
          FileUtils.remove_entry(outside) if outside
        end

        test "24 passes and objects still verify for the well-formed corpus" do
          result = verifier.call
          k24 = result.checks.find { |c| c[:check] == "24_manifest_keys_are_safe" }
          assert k24[:ok], k24[:detail]
        end

        # --- Finding 2: attachments table + unrelated tables ----------------

        test "27 passes when active_storage_attachments is identical to the parent" do
          check = verifier.call.checks.find { |c| c[:check] == "27_attachments_table_unchanged" }
          assert check[:ok], check[:detail]
        end

        test "27 fails when an attachment row was inserted" do
          @conn.attachments << @conn.attachments.first.merge("id" => "9999")
          check = verifier.call.checks.find { |c| c[:check] == "27_attachments_table_unchanged" }
          refute check[:ok]
          assert_includes check[:detail], "inserted=1"
        end

        test "27 fails when an attachment row's blob_id changed" do
          @conn.attachments.first["blob_id"] = "changed"
          check = verifier.call.checks.find { |c| c[:check] == "27_attachments_table_unchanged" }
          refute check[:ok]
          assert_includes check[:detail], "changed=1"
        end

        test "28 passes when unrelated table row counts match the parent" do
          check = verifier.call.checks.find { |c| c[:check] == "28_unrelated_table_row_counts_unchanged" }
          assert check[:ok], check[:detail]
        end

        test "28 fails when an unrelated table's row count drifted" do
          v3 = FakeConn.new(blobs: @blobs, video_struct: video_struct(@blobs), table_counts: { "users" => 4, "profiles" => 3 })
          parent = FakeConn.new(blobs: @parent_blobs, video_struct: video_struct(@parent_blobs),
            table_counts: { "users" => 3, "profiles" => 3 })
          check = Verifier.new(media_v3_connection: v3, parent_connection: parent, corpus_dir: @dir,
            manifest: @manifest, expected_object_count: 2).call.checks.find { |c| c[:check] == "28_unrelated_table_row_counts_unchanged" }
          refute check[:ok]
          assert_includes check[:detail], "users"
        end
      end
    end
  end
end
