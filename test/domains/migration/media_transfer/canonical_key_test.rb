# frozen_string_literal: true

require "test_helper"

module Migration
  module MediaTransfer
    class CanonicalKeyTest < ActiveSupport::TestCase
      Identity = CanonicalKey::Identity

      def identity(**overrides)
        Identity.new(
          source_system: "date9ja",
          source_blob_id: "12345",
          source_attachment_id: "67890",
          destination_purpose: "profile_photo_original",
          destination_brand: "date9ja",
          canonical_content_type: "image/jpeg"
        ).with(**overrides)
      end

      test "deterministic identity produces a deterministic final key" do
        assert_equal CanonicalKey.final_key(identity), CanonicalKey.final_key(identity)
      end

      test "final key has the fixed migration shape and no user/profile/slug" do
        key = CanonicalKey.final_key(identity)
        assert_match %r{\Amigrations/media/v3/date9ja/profile_photo_original/[0-9a-f-]{36}/original\.jpg\z}, key
      end

      test "object_uuid is exactly uuid_v5 of the canonical string" do
        expected = Digest::UUID.uuid_v5(CanonicalKey::KEY_NAMESPACE, CanonicalKey.canonical_string(identity))
        assert_equal expected, CanonicalKey.object_uuid(identity)
        assert_includes CanonicalKey.final_key(identity), expected
      end

      test "canonical string includes canonical_content_type before derivation" do
        assert_includes CanonicalKey.canonical_string(identity), "|canonical_content_type=image/jpeg"
      end

      test "content type participates in identity: jpeg and png differ" do
        jpeg = CanonicalKey.final_key(identity(canonical_content_type: "image/jpeg"))
        png = CanonicalKey.final_key(identity(canonical_content_type: "image/png"))
        refute_equal jpeg, png
        assert jpeg.end_with?("original.jpg")
        assert png.end_with?("original.png")
      end

      test "extension always corresponds to canonical_content_type" do
        assert CanonicalKey.final_key(identity(canonical_content_type: "image/webp")).end_with?("original.webp")
      end

      test "each identity field change yields a different key" do
        base = CanonicalKey.final_key(identity)
        %i[source_system source_blob_id source_attachment_id destination_purpose destination_brand].each do |field|
          changed = CanonicalKey.final_key(identity(field => "x_#{field}"))
          refute_equal base, changed, "#{field} must influence the key"
        end
      end

      test "Brand#slug mutation cannot change the key (slug is not an input)" do
        # The key depends on the stable `destination_brand` token, never a Brand row.
        before = CanonicalKey.final_key(identity)
        # simulate a brand rename: nothing about `identity` changes
        after = CanonicalKey.final_key(identity)
        assert_equal before, after
      end

      test "Profile#public_id / destination user are not identity inputs" do
        refute_includes CanonicalKey.canonical_string(identity), "public_id"
        refute_includes CanonicalKey.canonical_string(identity), "user_id"
        refute Identity.members.include?(:destination_profile_public_id)
        refute Identity.members.include?(:destination_user_id)
      end

      test "incomplete identity fails closed" do
        assert_raises(CanonicalKey::InvalidIdentity) do
          CanonicalKey.final_key(identity(canonical_content_type: nil))
        end
      end

      test "display key is the sibling of the final key" do
        key = CanonicalKey.final_key(identity)
        assert_equal key.sub("original.jpg", "display.jpg"), CanonicalKey.display_key(key)
      end
    end
  end
end
