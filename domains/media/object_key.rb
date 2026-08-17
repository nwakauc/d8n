module Media
  # Server-side allocator for R2/Active Storage object keys.
  #
  # D8N always allocates the storage key — the client never chooses it. Keys use
  # only stable, non-PII identifiers (brand slug, internal user id, profile
  # public UUID, and a freshly minted per-object UUID) joined with `/` so that
  # R2's flat keyspace renders as human-readable, brand-scoped folders in the
  # Cloudflare dashboard. No email, name, phone, username, or secret appears in a
  # key.
  #
  # The trailing `original.<ext>` marks the untouched upload. Future processed
  # variants live beside it under the same object UUID (`.../variants/<name>.ext`),
  # and future videos mirror this shape under `.../videos/<uuid>/...`.
  class ObjectKey
    EXTENSIONS = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/webp" => "webp"
    }.freeze
    DEFAULT_EXTENSION = "bin".freeze

    # Fixed basename for the safe, D8N-owned display derivative. Always JPEG.
    DISPLAY_BASENAME = "display.jpg".freeze
    ORIGINAL_BASENAME_PREFIX = "original.".freeze

    class << self
      # Key for the untouched original of a profile photo.
      def profile_photo_original(brand:, user:, profile:, content_type:, object_uuid: SecureRandom.uuid)
        join(
          photo_prefix(brand:, user:, profile:, object_uuid:),
          "original.#{extension_for(content_type)}"
        )
      end

      # Key for the safe display derivative, derived from the original's key so
      # it lands in the same `photos/<object_uuid>/` folder as its source. The
      # derivative is D8N-generated, so it never depends on client input.
      def profile_photo_display(original_key)
        segments = original_key.to_s.split("/")
        last = segments.last.to_s
        segments[-1] = DISPLAY_BASENAME if last.start_with?(ORIGINAL_BASENAME_PREFIX)
        # If the original basename is not where expected, keep the object folder
        # and append the display basename rather than silently colliding.
        segments << DISPLAY_BASENAME unless last.start_with?(ORIGINAL_BASENAME_PREFIX)
        segments.join("/")
      end

      # Logical folder for one photo object; variants hang off this prefix.
      def photo_prefix(brand:, user:, profile:, object_uuid:)
        join(
          profile_prefix(brand:, user:, profile:),
          "photos", object_uuid
        )
      end

      def extension_for(content_type)
        EXTENSIONS.fetch(content_type.to_s, DEFAULT_EXTENSION)
      end

      private

      def profile_prefix(brand:, user:, profile:)
        join(
          "brands", brand.slug,
          "users", user.id,
          "profiles", profile.public_id
        )
      end

      def join(*segments)
        segments.flatten.map(&:to_s).join("/")
      end
    end
  end
end
