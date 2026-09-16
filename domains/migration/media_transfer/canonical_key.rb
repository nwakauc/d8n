# frozen_string_literal: true

module Migration
  module MediaTransfer
    # The ONLY place a migration destination storage key is produced (ADR 0028
    # §3 / MEDIA-TRANSFER.md §7).
    #
    # The final key is a TOTAL deterministic function of the complete declared
    # canonical identity:
    #
    #   version | source_system | source_blob_id | source_attachment_id |
    #   destination_purpose | destination_brand | canonical_content_type
    #
    # No user id, no profile public id, no mutable Brand#slug lookup, no
    # destination Profile mapping. Destination remapping never re-keys — the
    # object is tied to the immutable source attachment identity; the
    # source Photo -> destination ProfilePhoto binding is Migration::ReferenceMap.
    #
    # This does NOT route through Media::ObjectKey.profile_photo_original, which
    # necessarily embeds user/profile/slug path segments.
    module CanonicalKey
      VERSION = "migration-media-transfer:v3"

      # One fixed, checked-in namespace. Changing it is a breaking key-scheme
      # change and must be a new VERSION.
      KEY_NAMESPACE = "5e63dfc4-8f83-41d9-92d1-c88065b87cff"

      KEY_ROOT = "migrations/media/v3"

      # ADR 0029: the ONLY canonical-identity change for video is these two
      # added rows (values already present in Media::ObjectKey::EXTENSIONS).
      # Everything else about the key — structure, VERSION, KEY_NAMESPACE,
      # KEY_ROOT, canonical_string, object_uuid — is unchanged.
      EXTENSIONS = {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        "video/mp4" => "mp4",
        "video/quicktime" => "mov"
      }.freeze

      # The complete declared canonical identity. `canonical_content_type` is the
      # verified detected media type (Media::PhotoUpload magic bytes), a property
      # of the immutable source bytes.
      Identity = Data.define(
        :source_system, :source_blob_id, :source_attachment_id,
        :destination_purpose, :destination_brand, :canonical_content_type
      )

      class InvalidIdentity < StandardError; end

      module_function

      def canonical_string(identity)
        assert_complete!(identity)
        VERSION +
          "|source_system=" + identity.source_system.to_s +
          "|source_blob_id=" + identity.source_blob_id.to_s +
          "|source_attachment_id=" + identity.source_attachment_id.to_s +
          "|destination_purpose=" + identity.destination_purpose.to_s +
          "|destination_brand=" + identity.destination_brand.to_s +
          "|canonical_content_type=" + identity.canonical_content_type.to_s
      end

      def object_uuid(identity)
        Digest::UUID.uuid_v5(KEY_NAMESPACE, canonical_string(identity))
      end

      def final_key(identity)
        [
          KEY_ROOT,
          identity.destination_brand.to_s,
          identity.destination_purpose.to_s,
          object_uuid(identity),
          "original.#{extension_for(identity.canonical_content_type)}"
        ].join("/")
      end

      # D8N-owned safe display derivative, beside the original on the same
      # private service (Media::ProcessProfilePhotoJob).
      def display_key(final_key)
        Media::ObjectKey.derived_key(final_key, Media::ObjectKey::DISPLAY_BASENAME)
      end

      def extension_for(content_type)
        EXTENSIONS.fetch(content_type.to_s) do
          raise InvalidIdentity, "unsupported canonical_content_type"
        end
      end

      def assert_complete!(identity)
        missing = identity.to_h.select { |_, v| v.to_s.strip.empty? }.keys
        raise InvalidIdentity, "incomplete canonical identity: #{missing.join(', ')}" if missing.any?
        raise InvalidIdentity, "source_system must be date9ja-shaped" unless identity.source_system.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
      end
    end
  end
end
