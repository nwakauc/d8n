module Identity
  # Control-plane/data-plane member submission of RealMe verification evidence
  # (selfie, liveness video, government ID), mirroring Profiles::PhotoUpload /
  # Profiles::VideoUpload: D8N allocates the object key and signs a short-lived
  # direct upload to private R2; bytes never pass through Puma. On completion,
  # D8N does a cheap magic-byte sniff + real-size bound and creates a `pending`
  # VerificationAssertion for a human reviewer (Trust::ModerateRealmeVerification)
  # — there is no automated face-match or document-match yet (deferred; see
  # docs/adr/0032-realme-manual-review-v1.md).
  class RealmeSubmission
    IMAGE_CONTENT_TYPES = ProfilePhoto::ALLOWED_CONTENT_TYPES
    VIDEO_CONTENT_TYPES = ProfileVideo::ALLOWED_CONTENT_TYPES
    MAX_IMAGE_BYTES = ProfilePhoto::MAX_FILE_SIZE
    # Independent of Media::VideoPolicy (a per-brand *product* feature toggle
    # for profile intro videos): RealMe liveness must work for a brand
    # regardless of whether it also offers profile videos.
    MAX_VIDEO_BYTES = 50.megabytes

    CHECK_TYPES = %w[selfie video government_id].freeze
    IMAGE_CHECK_TYPES = %w[selfie government_id].freeze

    UPLOAD_URL_EXPIRES_IN = 15.minutes

    Error = Class.new(StandardError)
    ProfileRequired = Class.new(Error)
    InvalidCheckType = Class.new(Error)
    InvalidContentType = Class.new(Error)
    InvalidSize = Class.new(Error)
    InvalidUpload = Class.new(Error)
    PendingSubmissionExists = Class.new(Error)
    MissingObject = Class.new(Error)
    InvalidObject = Class.new(Error)

    class << self
      def create_intent(user:, brand:, check_type:, filename:, byte_size:, checksum:, content_type:,
        storage_resolver: Media::StorageResolver)
        check_type = normalize_check_type!(check_type)
        require_profile!(user:, brand:)
        raise PendingSubmissionExists if pending?(user:, brand:, check_type:)

        content_type = content_type.to_s
        raise InvalidContentType unless allowed_content_types(check_type).include?(content_type)

        byte_size = Integer(byte_size, exception: false)
        max_bytes = max_byte_size(check_type)
        raise InvalidSize unless byte_size&.positive? && byte_size <= max_bytes

        checksum = checksum.to_s
        raise InvalidUpload if checksum.blank?

        key = Media::ObjectKey.realme_evidence_original(brand:, user:, check_type:, content_type:)
        service_name = storage_resolver.service_name(brand:)

        blob = ActiveStorage::Blob.create_before_direct_upload!(
          key:, filename: filename.to_s.presence || check_type,
          byte_size:, checksum:, content_type:, service_name:
        )

        {
          signed_id: blob.signed_id,
          url: blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
          headers: blob.service_headers_for_direct_upload,
          expires_in: UPLOAD_URL_EXPIRES_IN.to_i,
          byte_size_limit: max_bytes,
          allowed_content_types: allowed_content_types(check_type)
        }
      end

      def attach!(user:, brand:, check_type:, signed_id:)
        check_type = normalize_check_type!(check_type)
        require_profile!(user:, brand:)
        raise PendingSubmissionExists if pending?(user:, brand:, check_type:)

        blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
        raise InvalidUpload if blob.nil?
        raise InvalidUpload unless Media::StorageResolver.compatible_service?(brand:, service_name: blob.service_name)
        raise InvalidUpload if blob.attachments.exists?

        verify_uploaded_object!(blob, check_type:)

        assertion = VerificationAssertion.create!(
          brand:, user:, check_type:, status: "pending",
          submitted_at: Time.current,
          source_type: "member_submission", source_id: SecureRandom.uuid
        )
        assertion.evidence.attach(blob)
        assertion
      end

      def require_profile!(user:, brand:)
        Profile.kept.find_by(user:, brand:) || raise(ProfileRequired)
      end

      private

      def normalize_check_type!(check_type)
        check_type = check_type.to_s
        raise InvalidCheckType unless CHECK_TYPES.include?(check_type)

        check_type
      end

      def pending?(user:, brand:, check_type:)
        VerificationAssertion.where(brand:, user:, check_type:, status: "pending").exists?
      end

      def allowed_content_types(check_type)
        IMAGE_CHECK_TYPES.include?(check_type) ? IMAGE_CONTENT_TYPES : VIDEO_CONTENT_TYPES
      end

      def max_byte_size(check_type)
        IMAGE_CHECK_TYPES.include?(check_type) ? MAX_IMAGE_BYTES : MAX_VIDEO_BYTES
      end

      # Trust the object, not the client's declared metadata: confirm the
      # upload landed, sniff the real file signature, bound the real size, and
      # reconcile the blob to that verified truth before attachment. Reuses
      # the same magic-byte checks as Profiles::PhotoUpload / Profiles::VideoUpload.
      def verify_uploaded_object!(blob, check_type:)
        service = blob.service
        raise MissingObject unless service.exist?(blob.key)

        max_bytes = max_byte_size(check_type)
        detected_type = if IMAGE_CHECK_TYPES.include?(check_type)
          Profiles::PhotoUpload.detect_image_type(service.download_chunk(blob.key, 0...16))
        else
          detect_video_type(service.download_chunk(blob.key, 0...4096))
        end
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
