module Trust
  # Applies the narrow terminal moderation decision for a brand-scoped profile
  # photo. The profile lock keeps moderation, deletion, publication checks, and
  # the audit record atomic with the rest of the photo lifecycle.
  class ModerateProfilePhoto
    Error = Class.new(StandardError) do
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    DECISIONS = %w[approved rejected].freeze

    def self.call(admin_user:, brand:, photo_id:, decision:)
      target = decision.to_s
      raise Error, :invalid_photo_moderation_status unless DECISIONS.include?(target)

      photo = ProfilePhoto.kept.where(brand:).includes(:profile).find_by(public_id: photo_id)
      raise Error, :profile_photo_unavailable if photo.blank?

      transitioned = false
      ProfilePhoto.transaction do
        photo.profile.lock!
        photo.lock!
        photo.reload
        raise Error, :profile_photo_unavailable unless photo.kept?

        if photo.status != target
          raise Error, :profile_photo_moderation_conflict unless photo.pending_review?

          photo.update!(status: target, visibility: target == "approved" ? :visible : :hidden)
          Profiles::Publication.unpublish_if_incomplete!(profile: photo.profile)
          record_audit!(admin_user:, brand:, photo:, decision: target)
          transitioned = true
        end
      end

      Result.new(photo:, transitioned:)
    end

    Result = Data.define(:photo, :transitioned)

    def self.record_audit!(admin_user:, brand:, photo:, decision:)
      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type: "admin.profile_photo_moderated",
        severity: decision == "rejected" ? :warning : :info,
        metadata: {
          admin_user_id: admin_user.id,
          profile_id: photo.profile.public_id,
          profile_photo_id: photo.public_id,
          decision:,
          reason_code: "manual_moderation_decision"
        }
      )
    end
    private_class_method :record_audit!
  end
end
