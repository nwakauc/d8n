module Profiles
  # Control-plane/data-plane profile-video upload, mirroring Profiles::PhotoUpload
  # and Messaging::MessageAttachmentUpload (ADR 0023). D8N allocates the object
  # key and signs a short-lived direct upload to private R2; bytes never pass
  # through Puma. On completion D8N does a CHEAP magic-byte sniff + real-size
  # bound and attaches the one ProfileVideo for the profile. The full ISO-BMFF
  # structural walk and duration enforcement run asynchronously in
  # Media::ProcessProfileVideoJob (against the whole object — the `moov` box a
  # non-faststart MP4 puts at the end is not present in any bounded head), which
  # fails the video closed if it does not pass.
  class VideoUpload
    ALLOWED_CONTENT_TYPES = ProfileVideo::ALLOWED_CONTENT_TYPES
    UPLOAD_URL_EXPIRES_IN = 15.minutes
    RETRIEVAL_URL_EXPIRES_IN = 5.minutes

    Error = Class.new(StandardError)
    ProfileRequired = Class.new(Error)
    NotConfigured = Class.new(Error)
    InvalidContentType = Class.new(Error)
    InvalidSize = Class.new(Error)
    InvalidUpload = Class.new(Error)
    AlreadyAttached = Class.new(Error)
    InvalidObject = Class.new(Error)
    MissingObject = Class.new(Error)

    class << self
      def create_intent(user:, brand:, filename:, byte_size:, checksum:, content_type:,
        storage_resolver: Media::StorageResolver)
        profile = require_profile!(user:, brand:)
        max_bytes = max_byte_size!(brand:)

        content_type = content_type.to_s
        raise InvalidContentType unless ALLOWED_CONTENT_TYPES.include?(content_type)

        byte_size = Integer(byte_size, exception: false)
        raise InvalidSize unless byte_size&.positive? && byte_size <= max_bytes

        checksum = checksum.to_s
        raise InvalidUpload if checksum.blank?

        key = Media::ObjectKey.profile_video_original(brand:, user:, profile:, content_type:)
        service_name = storage_resolver.service_name(brand:)

        blob = ActiveStorage::Blob.create_before_direct_upload!(
          key:, filename: filename.to_s.presence || "video",
          byte_size:, checksum:, content_type:, service_name:
        )

        {
          signed_id: blob.signed_id,
          url: blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
          headers: blob.service_headers_for_direct_upload,
          expires_in: UPLOAD_URL_EXPIRES_IN.to_i,
          byte_size_limit: max_bytes,
          max_duration_seconds: Media::VideoPolicy.max_duration_seconds(brand:),
          allowed_content_types: ALLOWED_CONTENT_TYPES
        }
      end

      def attach!(user:, brand:, signed_id:)
        profile = require_profile!(user:, brand:)
        max_bytes = max_byte_size!(brand:)

        blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
        raise InvalidUpload if blob.nil?
        raise InvalidUpload unless Media::StorageResolver.compatible_service?(brand:, service_name: blob.service_name)
        raise AlreadyAttached if blob.attachments.exists?

        verify_uploaded_object!(blob, max_bytes:)

        initial = Media::VideoPolicy.initial_state(brand:)
        video = build_video!(
          profile:, user:, brand:, blob:,
          status: initial.status, visibility: initial.visibility
        )

        Media::ProcessProfileVideoJob.perform_later(video.id)
        video
      end

      # Minimal internal domain seam (mirrors Profiles::PhotoUpload.build_photo!;
      # ADR 0029 Pass 2B). Owns ProfileVideo DOMAIN invariants only — validity,
      # owner/profile/brand scope, blob-not-already-attached, one-live-video-per-
      # profile — under the profile lock. It does NOT own request
      # authentication/authorization (the HTTP `attach!` path keeps that) or
      # policy-state derivation (Media::VideoPolicy.initial_state).
      # Date9ja::Import::VideoTransfer calls this with explicit source-derived
      # status/visibility, after its own Migration::MediaTransfer verification
      # and inside its Phase-B transaction.
      def build_video!(profile:, user:, brand:, blob:, status:, visibility:)
        profile.with_lock do
          raise AlreadyAttached if blob.attachments.exists?
          raise AlreadyAttached if ProfileVideo.kept.exists?(profile:)

          record = ProfileVideo.new(profile:, user:, brand:, status:, visibility:)
          record.video.attach(blob)
          record.save!
          record
        end
      end

      def require_profile!(user:, brand:)
        Profile.kept.find_by(user:, brand:) || raise(ProfileRequired)
      end

      private

      def max_byte_size!(brand:)
        Media::VideoPolicy.max_byte_size(brand:)
      rescue Media::VideoPolicy::NotConfigured
        raise NotConfigured
      end

      # Trust the object, not the client: confirm the upload landed, cheaply
      # confirm it is an ISO-BMFF container (the `ftyp` box always sits at
      # offset 4), bound the real size, and reconcile the blob to that. The full
      # box-tree walk + codec + duration checks run in the async job against the
      # whole object.
      def verify_uploaded_object!(blob, max_bytes:)
        service = blob.service
        raise MissingObject unless service.exist?(blob.key)

        head = service.download_chunk(blob.key, 0...4096).to_s.b
        detected_type = detect_video_type(head)
        raise InvalidObject if detected_type.nil?

        actual_size = object_byte_size(service, blob.key, max_bytes:)
        raise InvalidSize if actual_size.nil? || actual_size <= 0 || actual_size > max_bytes

        blob.update!(content_type: detected_type, byte_size: actual_size)
      end

      def detect_video_type(head)
        bytes = head.to_s.b
        return nil if bytes.bytesize < 12
        return nil unless bytes[4, 4] == "ftyp"

        bytes[8, 4].to_s == "qt  " ? "video/quicktime" : "video/mp4"
      end

      def object_byte_size(service, key, max_bytes:)
        if service.respond_to?(:bucket)
          service.bucket.object(key).content_length
        else
          service.download_chunk(key, 0...(max_bytes + 1)).bytesize
        end
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
