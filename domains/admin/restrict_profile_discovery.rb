module Admin
  # Moderator "hide from discovery" (mirrors Date9ja's own discovery_restricted_at/
  # reason/note/restricted_by columns). Deliberately lighter than SuspendProfile:
  # no BrandMembership status change, no session revocation, no AccountEnforcement
  # row. A restricted member stays logged in and active; they are simply excluded
  # from discovery and direct profile view by other members (Matching::
  # VisibilityScope), distinguishable in Member 360/discovery diagnostic from
  # member-pause, incomplete-profile, suspension, and ban.
  class RestrictProfileDiscovery
    def self.call(admin_user:, brand:, profile_public_id:, reason:, note: nil)
      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      reason_text = normalize_reason(reason)
      raise ModerationError, :invalid_reason if reason_text.blank?

      profile.with_lock do
        raise ModerationError, :already_restricted if profile.discovery_restricted_at.present?

        profile.update!(
          discovery_restricted_at: Time.current,
          discovery_restriction_reason: reason_text,
          discovery_restriction_note: normalize_note(note),
          discovery_restricted_by_admin_user: admin_user
        )
      end

      record_audit!(admin_user:, profile:, event_type: "admin.discovery_restricted", severity: :warning)
      profile
    end

    def self.normalize_reason(reason)
      text = reason.to_s.strip
      return if text.blank?
      raise ModerationError, :invalid_reason if text.length > 500

      text
    end
    private_class_method :normalize_reason

    def self.normalize_note(note)
      text = note.to_s.strip
      raise ModerationError, :invalid_note if text.length > 2_000

      text.presence
    end
    private_class_method :normalize_note

    def self.record_audit!(admin_user:, profile:, event_type:, severity:)
      SecurityEvent.create!(
        brand: profile.brand,
        user: admin_user.user,
        event_type:,
        severity:,
        metadata: {
          admin_user_id: admin_user.id,
          target_profile_id: profile.id,
          target_user_id: profile.user_id,
          has_reason: profile.discovery_restriction_reason.present?,
          has_note: profile.discovery_restriction_note.present?
        }
      )
    end
    private_class_method :record_audit!
  end
end
