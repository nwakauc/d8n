module Admin
  # Applies a brand-level suspension to a profile's owner, atomically: suspend the
  # BrandMembership (the gate every product/auth surface already checks), revoke
  # every active session that user holds on this brand, create the durable
  # AccountEnforcement record, and audit — all in one transaction so we never end
  # up "audited but still active" or "suspended but sessions still valid".
  #
  # Brand-scoped: the target is resolved within the moderator's brand; a
  # cross-brand or unknown profile is a neutral `profile_unavailable`. The suspended
  # user's identity and any other-brand sessions are untouched (multi-brand safe).
  # An optional report links the enforcement to its cause without changing the
  # report's own lifecycle. Idempotency/concurrency is handled by the active-unique
  # index plus a membership row lock.
  class SuspendProfile
    def self.call(admin_user:, brand:, profile_public_id:, reason: nil, report_id: nil, note: nil, kind: :suspension)
      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      report = resolve_report(brand:, report_id:)
      reason_text = normalize_reason(reason)
      kind = kind.to_sym
      raise ModerationError, :invalid_kind unless %i[suspension ban].include?(kind)
      raise ModerationError, :invalid_reason if kind == :ban && reason_text.blank?

      enforcement = nil
      ActiveRecord::Base.transaction do
        membership = BrandMembership.lock.find(profile.brand_membership_id)
        raise ModerationError, :already_suspended if active_enforcement?(brand:, user_id: profile.user_id)
        raise ModerationError, :already_suspended if membership.suspended?
        raise ModerationError, :profile_unavailable unless membership.active?

        membership.update!(status: :suspended)
        revoke_sessions(user: profile.user, brand:)
        enforcement = AccountEnforcement.create!(
          brand:, user: profile.user, brand_membership: membership, profile:,
          admin_user:, report:, reason: reason_text, note: normalize_note(note), kind:
        )
        EnforcementAudit.record(
          admin_user:, enforcement:, event_type: kind == :ban ? "admin.account_banned" : "admin.account_suspended", severity: kind == :ban ? :high : :warning
        )
      end
      enforcement
    rescue ActiveRecord::RecordNotUnique
      raise ModerationError, :already_suspended
    end

    def self.active_enforcement?(brand:, user_id:)
      AccountEnforcement.active.exists?(brand:, user_id:)
    end
    private_class_method :active_enforcement?

    def self.revoke_sessions(user:, brand:)
      Session.active.where(user:, brand:).find_each do |session|
        Identity::SessionRevoker.call(session:)
      end
    end
    private_class_method :revoke_sessions

    def self.resolve_report(brand:, report_id:)
      return if report_id.blank?

      Report.where(brand:).find_by(id: report_id) || raise(ModerationError, :invalid_report)
    end
    private_class_method :resolve_report

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
  end
end
