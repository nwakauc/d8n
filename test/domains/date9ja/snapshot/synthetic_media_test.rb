# frozen_string_literal: true

require "test_helper"
require "vips"

module Date9ja
  module Snapshot
    class SyntheticMediaTest < ActiveSupport::TestCase
      test "render is a total deterministic function of (version, seed, blob id, content type)" do
        a = SyntheticMedia.render(source_blob_id: "42", canonical_content_type: "image/jpeg", seed: "s1")
        b = SyntheticMedia.render(source_blob_id: "42", canonical_content_type: "image/jpeg", seed: "s1")
        c = SyntheticMedia.render(source_blob_id: "42", canonical_content_type: "image/jpeg", seed: "s2")
        d = SyntheticMedia.render(source_blob_id: "43", canonical_content_type: "image/jpeg", seed: "s1")

        assert_equal a, b
        refute_equal a, c
        refute_equal a, d
      end

      test "render produces a bounded, decodable image of the requested container type" do
        {
          "image/jpeg" => "\xFF\xD8\xFF".b,
          "image/png" => "\x89PNG\r\n\x1A\n".b,
          "image/webp" => nil
        }.each do |content_type, magic|
          bytes = SyntheticMedia.render(source_blob_id: "7", canonical_content_type: content_type, seed: "x")

          assert_operator bytes.bytesize, :<=, SyntheticMedia::BYTE_CEILING
          assert_equal content_type, Profiles::PhotoUpload.detect_image_type(bytes[0, 16])
          assert_equal magic, bytes[0, magic.bytesize] if magic
          assert_nothing_raised { Media::ImageProcessor.call(bytes) }
        end
      end

      test "render rejects an unsupported canonical content type" do
        assert_raises(ArgumentError) do
          SyntheticMedia.render(source_blob_id: "1", canonical_content_type: "image/gif", seed: "x")
        end
      end

      test "keystream is deterministic and the requested length" do
        s1 = SyntheticMedia.keystream(1024, "m")
        s2 = SyntheticMedia.keystream(1024, "m")

        assert_equal 1024, s1.bytesize
        assert_equal s1, s2
        refute_equal s1, SyntheticMedia.keystream(1024, "n")
      end
    end
  end
end
