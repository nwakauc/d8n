module Admin
  # Publishes a brand profile from HQ after the normal publication checks pass.
  # This is deliberately narrower than an arbitrary status update: active
  # enforcement and moderator discovery restrictions remain authoritative.
  class PublishProfile
    def self.call(admin_user:, brand:, profile_public_id:, reason:)
      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      reason_text = normalize_reason(reason)
      raise ModerationError, :invalid_reason if reason_text.blank?

      raise ModerationError, :already_visible if profile.active? && profile.visible?
      raise ModerationError, :enforced if AccountEnforcement.active.exists?(brand:, user_id: profile.user_id)
      raise ModerationError, :discovery_restricted if profile.discovery_restricted_at.present?

      begin
        Profiles::Publication.activate!(user: profile.user, brand:)
      rescue Profiles::Publication::Incomplete
        raise ModerationError, :profile_incomplete
      rescue Profiles::Publication::Unavailable
        raise ModerationError, :enforced
      end

      SecurityEvent.create!(
        brand:, user: admin_user.user, event_type: "admin.profile_published",
        severity: :info,
        metadata: {
          admin_user_id: admin_user.id,
          target_profile_id: profile.id,
          target_user_id: profile.user_id,
          reason_present: reason_text.present?
        }
      )

      profile.reload
    end

    def self.normalize_reason(reason)
      text = reason.to_s.strip
      return if text.blank?
      raise ModerationError, :invalid_reason if text.length > 500

      text
    end
    private_class_method :normalize_reason
  end
end
