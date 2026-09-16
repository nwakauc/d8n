module Admin
  # Lifts a moderator discovery restriction (Admin::RestrictProfileDiscovery).
  # Restores ONLY what the restriction changed -- discovery/direct-profile
  # visibility. Does not touch account status, sessions, or any other
  # enforcement (suspension/ban remain independently in force if also present).
  class LiftProfileDiscoveryRestriction
    def self.call(admin_user:, brand:, profile_public_id:)
      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      had_reason = nil
      profile.with_lock do
        raise ModerationError, :not_restricted if profile.discovery_restricted_at.blank?

        had_reason = profile.discovery_restriction_reason.present?
        profile.update!(
          discovery_restricted_at: nil,
          discovery_restriction_reason: nil,
          discovery_restriction_note: nil,
          discovery_restricted_by_admin_user: nil
        )
      end

      record_audit!(admin_user:, profile:, had_reason:)
      profile
    end

    def self.record_audit!(admin_user:, profile:, had_reason:)
      SecurityEvent.create!(
        brand: profile.brand,
        user: admin_user.user,
        event_type: "admin.discovery_restriction_lifted",
        severity: :info,
        metadata: {
          admin_user_id: admin_user.id,
          target_profile_id: profile.id,
          target_user_id: profile.user_id,
          had_reason:
        }
      )
    end
    private_class_method :record_audit!
  end
end
