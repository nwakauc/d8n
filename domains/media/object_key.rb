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
      "image/webp" => "webp",
      "video/mp4" => "mp4",
      "video/quicktime" => "mov"
    }.freeze
    DEFAULT_EXTENSION = "bin".freeze

    # Fixed basename for the safe, D8N-owned display derivative. Always JPEG.
    DISPLAY_BASENAME = "display.jpg".freeze
    ORIGINAL_BASENAME_PREFIX = "original.".freeze
    POSTER_BASENAME = "poster.jpg".freeze
    # Video playback rendition (Media::VideoProcessor output — H.264/AAC MP4,
    # or a stream-copy remux; see that class). Always MP4.
    PLAYBACK_BASENAME = "playback.mp4".freeze
    # Higher-fidelity, still-sanitized image derivative served only to an
    # authorized downloader — never the untouched original (see
    # domains/messaging/message_serializer.rb).
    DOWNLOAD_BASENAME = "download.jpg".freeze

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
        derived_key(original_key, DISPLAY_BASENAME)
      end

      # Shared "replace the original.<ext> basename with a fixed derivative
      # basename in the same object folder" logic, used by both the profile
      # photo display derivative and message attachment poster/rendition keys.
      def derived_key(original_key, basename)
        segments = original_key.to_s.split("/")
        last = segments.last.to_s
        segments[-1] = basename if last.start_with?(ORIGINAL_BASENAME_PREFIX)
        # If the original basename is not where expected, keep the object folder
        # and append the derivative basename rather than silently colliding.
        segments << basename unless last.start_with?(ORIGINAL_BASENAME_PREFIX)
        segments.join("/")
      end

      # Logical folder for one photo object; variants hang off this prefix.
      def photo_prefix(brand:, user:, profile:, object_uuid:)
        join(
          profile_prefix(brand:, user:, profile:),
          "photos", object_uuid
        )
      end

      # Key for the untouched original of a profile introduction video.
      def profile_video_original(brand:, user:, profile:, content_type:, object_uuid: SecureRandom.uuid)
        join(
          video_prefix(brand:, user:, profile:, object_uuid:),
          "original.#{extension_for(content_type)}"
        )
      end

      # Safe playback rendition (Media::VideoProcessor output) beside the original.
      def profile_video_playback(original_key)
        derived_key(original_key, PLAYBACK_BASENAME)
      end

      # Poster frame (Media::VideoProcessor + Media::ImageProcessor) beside the original.
      def profile_video_poster(original_key)
        derived_key(original_key, POSTER_BASENAME)
      end

      # Logical folder for one profile video object; renditions hang off this prefix.
      def video_prefix(brand:, user:, profile:, object_uuid:)
        join(
          profile_prefix(brand:, user:, profile:),
          "videos", object_uuid
        )
      end

      # Key for the untouched original of a chat message attachment (image or
      # video). Scoped under the sender's own user id and the conversation's
      # public id — never the recipient's identity, and never a message id
      # (which is only allocated once the attachment is already finalized).
      def message_attachment_original(brand:, user:, conversation:, content_type:, object_uuid: SecureRandom.uuid)
        join(
          attachment_prefix(brand:, user:, conversation:, object_uuid:),
          "original.#{extension_for(content_type)}"
        )
      end

      # Key for the video poster/thumbnail. Server-generated (Media::VideoProcessor
      # frame extraction, re-encoded through Media::ImageProcessor) — the
      # production source of truth; lands beside the original in the same
      # attachment folder.
      def message_attachment_poster(original_key)
        derived_key(original_key, POSTER_BASENAME)
      end

      # Key for the image inline-view derivative (re-encoded/EXIF-stripped,
      # bandwidth-friendly — see Media::ImageProcessor::DISPLAY_MAX_DIMENSION).
      def message_attachment_rendition(original_key)
        derived_key(original_key, DISPLAY_BASENAME)
      end

      # Key for the video playback rendition (Media::VideoProcessor output).
      def message_attachment_playback(original_key)
        derived_key(original_key, PLAYBACK_BASENAME)
      end

      # Key for the sanitized, higher-fidelity image derivative served on
      # explicit download — never the raw original (EXIF/GPS privacy; see
      # Messaging::MessageSerializer).
      def message_attachment_download(original_key)
        derived_key(original_key, DOWNLOAD_BASENAME)
      end

      def attachment_prefix(brand:, user:, conversation:, object_uuid:)
        join(
          "brands", brand.slug,
          "users", user.id,
          "conversations", conversation.public_id,
          "attachments", object_uuid
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
