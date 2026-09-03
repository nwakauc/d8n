# frozen_string_literal: true

require "test_helper"
require "vips"

module Date9ja
  module Snapshot
    module SyntheticMedia
      # Minimal in-memory stand-in for the media_v2 / parent snapshot connections.
      # Models a tiny active_storage_blobs table + the Photo image attachment
      # graph so the verifier's schema-driven / graph-driven queries resolve.
      class FakeConn
        Row = Struct.new(:to_a)
        BLOB_COLUMNS = %w[id key filename content_type metadata service_name byte_size checksum created_at].freeze

        # `blobs` rows carry at least id/key/content_type/service_name/byte_size/checksum.
        # Every blob is treated as a Photo image attachment unless :non_photo is true.
        def initialize(blobs:, photo_struct: nil)
          @blobs = blobs.map { |b| normalize(b) }
          @src = blobs
          @photo_struct = photo_struct
        end

        attr_reader :blobs

        def add_row!(hash) = @blobs << normalize(hash)

        def normalize(b)
          BLOB_COLUMNS.to_h { |c| [ c, b.fetch(c, default_for(c, b)) ] }.merge("_non_photo" => b["_non_photo"])
        end

        def exec_query(sql, *)
          Row.new(
            if sql.include?("information_schema.columns")
              BLOB_COLUMNS.map { |c| { "column_name" => c } }
            elsif sql.include?("FROM photos")
              @photo_struct || default_photo_struct
            elsif sql.include?("FROM active_storage_attachments") && !sql.include?("JOIN")
              photo_blobs.map { |b| { "blob_id" => b["id"] } }
            elsif sql.include?("FROM active_storage_blobs") && sql.include?("WHERE id IN")
              ids = sql[/WHERE id IN \(([^)]*)\)/, 1].split(",").map(&:strip)
              @blobs.select { |b| ids.include?(b["id"].to_s) }
                .map { |b| b.slice("id", "key", "service_name", "content_type", "byte_size", "checksum") }
            elsif sql.include?("FROM active_storage_blobs") && !sql.include?("JOIN")
              @blobs.map { |b| b.slice(*BLOB_COLUMNS) }
            else
              # generator BLOB_QUERY (blobs JOIN attachments)
              photo_blobs.map { |b| b.slice("id", "key", "content_type", "service_name") }
            end
          )
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

        def photo_blobs = @blobs.reject { |b| b["_non_photo"] }

        def default_for(col, blob)
          case col
          when "filename" then "file-#{blob['id']}.jpg"
          when "metadata" then "{}"
          when "created_at" then "2024-01-01 00:00:00"
          when "byte_size" then 0
          when "checksum" then ""
          else nil
          end
        end

        def default_photo_struct
          photo_blobs.each_with_index.map do |b, i|
            {
              "photo_id" => (i + 1).to_s, "user_id" => (100 + i).to_s, "position" => i.to_s,
              "moderation_status" => "1", "is_primary" => (i.zero? ? "1" : "0"),
              "attachment_id" => (500 + i).to_s, "blob_id" => b["id"],
              "key" => b["key"], "content_type" => b["content_type"], "service_name" => b["service_name"]
            }
          end
        end
      end

      class GeneratorTest < ActiveSupport::TestCase
        setup do
          @dir = Dir.mktmpdir("gen-test")
          @blobs = [
            { "id" => "1", "key" => "snapshot/1/aaa", "content_type" => "image/jpeg", "service_name" => "cloudflare",
              "byte_size" => 111, "checksum" => "old1" },
            { "id" => "2", "key" => "snapshot/2/bbb", "content_type" => "image/png", "service_name" => "cloudflare",
              "byte_size" => 222, "checksum" => "old2" },
            { "id" => "3", "key" => "snapshot/3/ccc", "content_type" => "image/webp", "service_name" => "cloudflare",
              "byte_size" => 333, "checksum" => "old3" }
          ]
          @conn = FakeConn.new(blobs: @blobs)
        end

        teardown { FileUtils.remove_entry(@dir) }

        test "renders one bounded, decodable object per blob and writes a fingerprinted manifest" do
          generator = Generator.new(connection: @conn, corpus_dir: @dir, seed: "t")
          result = generator.call

          assert_equal 3, result.object_count
          assert_equal({ "image/jpeg" => 1, "image/png" => 1, "image/webp" => 1 }, result.content_type_counts)

          manifest = JSON.parse(File.read(result.manifest_path))
          assert_equal 3, manifest["object_count"]
          assert_equal Generator.fingerprint_of(manifest), result.manifest_fingerprint
          assert_equal result.manifest_fingerprint.strip, File.read(generator.fingerprint_path).strip

          manifest["objects"].each do |o|
            path = File.join(@dir, "objects", o["source_key"])
            bytes = File.binread(path)
            assert_equal bytes.bytesize, o["byte_size"]
            assert_equal Digest::MD5.base64digest(bytes), o["checksum"]
            assert_equal o["canonical_content_type"], Profiles::PhotoUpload.detect_image_type(bytes[0, 16])
            assert_nothing_raised { Media::ImageProcessor.call(bytes) }
          end
        end

        test "rewrites only byte_size and checksum on the media_v2 blob rows" do
          Generator.new(connection: @conn, corpus_dir: @dir, seed: "t").call

          @blobs.each do |b|
            refute_equal "old#{b['id']}", b["checksum"]
            assert_operator b["byte_size"], :>, 0
            assert_equal "cloudflare", b["service_name"]
            assert b["key"].start_with?("snapshot/")
          end
        end

        test "is byte-for-byte deterministic across two runs into separate dirs" do
          r1 = Generator.new(connection: @conn, corpus_dir: @dir, seed: "t", patch_metadata: false).call
          other = Dir.mktmpdir("gen-test-2")
          r2 = Generator.new(connection: FakeConn.new(blobs: Marshal.load(Marshal.dump(@blobs))),
            corpus_dir: other, seed: "t", patch_metadata: false).call

          assert_equal r1.manifest_fingerprint, r2.manifest_fingerprint
          Dir.glob(File.join(@dir, "objects", "**", "*")).select { |f| File.file?(f) }.each do |f|
            rel = f.delete_prefix("#{@dir}/")
            assert_equal File.binread(f), File.binread(File.join(other, rel))
          end
        ensure
          FileUtils.remove_entry(other) if other
        end
      end

      class GeneratorPathSafetyTest < ActiveSupport::TestCase
        setup { @dir = Dir.mktmpdir("gen-path-test") }
        teardown { FileUtils.remove_entry(@dir) }

        def conn_with(key)
          FakeConn.new(blobs: [
            { "id" => "1", "key" => key, "content_type" => "image/jpeg", "service_name" => "cloudflare",
              "byte_size" => 0, "checksum" => "" }
          ])
        end

        def generate(key)
          Generator.new(connection: conn_with(key), corpus_dir: @dir, seed: "p", patch_metadata: false).call
        end

        test "a normal flat storage key writes successfully" do
          generate("flatobject")
          assert File.file?(File.join(@dir, "objects", "flatobject"))
        end

        test "a normal nested safe key writes successfully and is readable by LocalCorpusReader" do
          generate("snapshot/1/4f1ac30dcdf2af8efcf44f77e8196d1e")
          reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir: @dir)
          assert reader.head("snapshot/1/4f1ac30dcdf2af8efcf44f77e8196d1e")
        end

        {
          "single ../ escape" => "../evil",
          "nested ../../ escape" => "a/../../evil",
          "absolute path" => "/etc/evil",
          "backslash traversal" => "a\\..\\evil",
          "percent-encoded traversal" => "a/%2e%2e/evil",
          "query character" => "a?b",
          "fragment character" => "a#b",
          "control character" => "a\x01b",
          "whitespace" => "a b"
        }.each do |label, key|
          test "rejects #{label} and creates no file" do
            assert_raises(Date9ja::Storage::SafeObjectKey::InvalidKey) { generate(key) }
            written = Dir.glob(File.join(@dir, "objects", "**", "*")).select { |f| File.file?(f) }
            assert_empty written, "no object may be written for a rejected key"
          end
        end

        test "rejects a symlinked corpus parent that escapes the root and writes nothing outside" do
          outside = Dir.mktmpdir("gen-outside")
          FileUtils.mkdir_p(File.join(@dir, "objects", "snapshot"))
          File.symlink(outside, File.join(@dir, "objects", "snapshot", "evil"))

          assert_raises(Date9ja::Storage::SafeObjectKey::UnsafePath) { generate("snapshot/evil/obj") }
          assert_empty Dir.children(outside)
        ensure
          FileUtils.remove_entry(outside)
        end

        test "the generator's accepted key set matches LocalCorpusReader's" do
          [ "abc", "snapshot/1/x", "a-b_c=d/e" ].each do |k|
            assert Date9ja::Storage::SafeObjectKey.valid?(k)
          end
          [ "../x", "/x", "a/../x", "a b" ].each do |k|
            refute Date9ja::Storage::SafeObjectKey.valid?(k)
          end
        end
      end

      class VerifierTest < ActiveSupport::TestCase
        setup do
          @dir = Dir.mktmpdir("ver-test")
          @blobs = [
            { "id" => "1", "key" => "snapshot/1/aaa", "content_type" => "image/jpeg", "service_name" => "cloudflare",
              "byte_size" => 0, "checksum" => "" },
            { "id" => "2", "key" => "snapshot/2/bbb", "content_type" => "image/png", "service_name" => "cloudflare",
              "byte_size" => 0, "checksum" => "" }
          ]
          @parent_blobs = Marshal.load(Marshal.dump(@blobs)) # pre-generation integrity metadata
          @conn = FakeConn.new(blobs: @blobs, photo_struct: photo_struct(@blobs))
          Generator.new(connection: @conn, corpus_dir: @dir, seed: "v").call
          @manifest = JSON.parse(File.read(File.join(@dir, "manifest.json")))
        end

        teardown { FileUtils.remove_entry(@dir) }

        def photo_struct(blobs)
          blobs.reject { |b| b["_non_photo"] }.each_with_index.map do |b, i|
            {
              "photo_id" => (i + 1).to_s, "user_id" => (100 + i).to_s, "position" => i.to_s,
              "moderation_status" => "1", "is_primary" => (i.zero? ? "1" : "0"),
              "attachment_id" => (500 + i).to_s, "blob_id" => b["id"],
              "key" => b["key"], "content_type" => b["content_type"], "service_name" => b["service_name"]
            }
          end
        end

        def verifier(parent_blobs: @parent_blobs, expected_object_count: 2)
          parent = FakeConn.new(blobs: parent_blobs, photo_struct: photo_struct(parent_blobs))
          Verifier.new(media_v2_connection: @conn, parent_connection: parent,
            corpus_dir: @dir, manifest: @manifest, expected_object_count:)
        end

        test "passes every check for a well-formed corpus" do
          result = verifier.call

          assert result.ok?, result.failures.map { |c| "#{c[:check]}:#{c[:detail]}" }.join(", ")
          assert_equal 2, result.object_count
        end

        test "fails 05/06 when a stored object is tampered" do
          path = File.join(@dir, "objects", @manifest["objects"].first["source_key"])
          File.binwrite(path, File.binread(path) + "tampered".b)

          result = verifier.call

          refute result.ok?
          failed = result.failures.map { |c| c[:check] }
          assert_includes failed, "06_byte_size_matches_bytes"
          assert_includes failed, "05_checksum_matches_bytes"
        end

        test "fails 03 when a stored object is missing" do
          FileUtils.rm(File.join(@dir, "objects", @manifest["objects"].first["source_key"]))

          assert_includes verifier.call.failures.map { |c| c[:check] }, "03_every_object_present"
        end

        test "fails 09 when media_v2 structural identity drifts from the parent" do
          drifted = Marshal.load(Marshal.dump(@blobs))
          drifted.first["content_type"] = "image/webp" # a real identity change

          failed = verifier(parent_blobs: drifted).call.failures.map { |c| c[:check] }
          assert_includes failed, "09_no_source_identity_drift"
        end

        test "fails 02 when the manifest references an object media_v2 does not have" do
          @manifest["objects"] << @manifest["objects"].first.merge("source_blob_id" => "999")

          assert_includes verifier.call.failures.map { |c| c[:check] }, "02_no_unexpected_objects"
        end

        # --- FIX 2: manifest <-> media_v2 blob-row binding ---------------------

        test "16 passes when every manifest field binds to the authoritative blob row" do
          check = verifier.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v2_blobs" }
          assert check[:ok], check[:detail]
        end

        test "16 fails on a manifest source_key / service_name / content_type mismatch" do
          @manifest["objects"].first["source_key"] = "snapshot/1/WRONGKEY"
          @manifest["objects"].last["service_name"] = "amazon"

          check = verifier.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v2_blobs" }
          refute check[:ok]
          assert_includes check[:detail], "source_key"
          assert_includes check[:detail], "service_name"
        end

        test "16 fails on a duplicate source_blob_id in the manifest" do
          @manifest["objects"] << @manifest["objects"].first.dup

          check = verifier.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v2_blobs" }
          refute check[:ok]
          assert_includes check[:detail], "duplicate_source_blob_id=1"
        end

        test "canonical_byte_size accepts only non-negative JSON integers" do
          v = verifier
          assert_equal 123, v.send(:canonical_byte_size, 123)
          assert_nil v.send(:canonical_byte_size, "123")      # strings not in the manifest contract
          assert_nil v.send(:canonical_byte_size, "123junk")
          assert_nil v.send(:canonical_byte_size, " 123")
          assert_nil v.send(:canonical_byte_size, "123.0")
          assert_nil v.send(:canonical_byte_size, 123.0)       # float
          assert_nil v.send(:canonical_byte_size, nil)
          assert_nil v.send(:canonical_byte_size, true)
          assert_nil v.send(:canonical_byte_size, -1)
        end

        test "16 fails when manifest byte_size is malformed numeric text" do
          real = @manifest["objects"].first["byte_size"]
          @manifest["objects"].first["byte_size"] = "#{real}junk"

          check = verifier.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v2_blobs" }
          refute check[:ok]
          assert_includes check[:detail], "byte_size"
        end

        test "16 rejects float / nil / boolean / negative manifest byte_size" do
          [ 123.0, nil, true, -1 ].each do |bad|
            m = JSON.parse(JSON.generate(@manifest))
            m["objects"].first["byte_size"] = bad
            parent = FakeConn.new(blobs: @parent_blobs, photo_struct: photo_struct(@parent_blobs))
            v = Verifier.new(media_v2_connection: @conn, parent_connection: parent,
              corpus_dir: @dir, manifest: m, expected_object_count: 2)
            check = v.call.checks.find { |c| c[:check] == "16_manifest_rows_match_media_v2_blobs" }
            refute check[:ok], "expected byte_size #{bad.inspect} to be rejected"
          end
        end

        # --- FIX 3: complete blob-table drift proof ---------------------------

        test "db_value_equal? distinguishes NULL, empty string, zero and false" do
          v = verifier
          assert v.send(:db_value_equal?, nil, nil)
          assert v.send(:db_value_equal?, "", "")
          assert v.send(:db_value_equal?, 5, 5)
          refute v.send(:db_value_equal?, nil, "")
          refute v.send(:db_value_equal?, "", nil)
          refute v.send(:db_value_equal?, 0, false)
          refute v.send(:db_value_equal?, 0, "0")
        end

        test "17 fails when a non-Photo blob column goes from SQL NULL to empty string" do
          @conn.add_row!({ "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "c", "metadata" => "", "_non_photo" => true })
          parent = @parent_blobs + [ { "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "c", "metadata" => nil, "_non_photo" => true } ]

          check = verifier(parent_blobs: parent).call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "non_photo_change=1"
        end

        test "17 fails when an authorized Photo blob changes a non-mutable column from NULL to ''" do
          @conn.blobs.first["metadata"] = ""
          parent = Marshal.load(Marshal.dump(@parent_blobs))
          parent.first["metadata"] = nil

          check = verifier(parent_blobs: parent).call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "wrong_column_change=1"
        end


        test "17 passes when only byte_size/checksum changed on the authorized Photo set" do
          check = verifier.call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          assert check[:ok], check[:detail]
          assert_includes check[:detail], "wrong_column_change=0 non_photo_change=0"
          assert_includes check[:detail], "inserted=0 deleted=0"
        end

        test "17 fails when a non-mutable column changed on a Photo blob" do
          @conn.blobs.first["filename"] = "renamed.jpg" # not byte_size / checksum

          check = verifier.call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "wrong_column_change=1"
        end

        test "17 fails when a non-Photo blob row changed" do
          @conn.add_row!({ "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "v2only", "_non_photo" => true })
          parent = @parent_blobs + [ { "id" => "9", "key" => "avatars/9/x", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 10, "checksum" => "parent", "_non_photo" => true } ]

          check = verifier(parent_blobs: parent).call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "non_photo_change=1"
        end

        test "17 fails when a blob row was inserted" do
          @conn.add_row!({ "id" => "9", "key" => "x/9/y", "content_type" => "image/jpeg",
            "service_name" => "cloudflare", "byte_size" => 1, "checksum" => "z", "_non_photo" => true })

          check = verifier.call.checks.find { |c| c[:check] == "17_complete_blob_table_drift_is_authorized" }
          refute check[:ok]
          assert_includes check[:detail], "inserted=1"
        end
      end
    end
  end
end
