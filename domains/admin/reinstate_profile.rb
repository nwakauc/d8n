module Admin
  # Lifts a brand-level suspension: reactivate the BrandMembership, mark the
  # enforcement reverted, and audit — atomically. Reinstatement restores ONLY what
  # suspension changed. It does NOT revive revoked sessions (the user simply logs
  # in again), ended matches, blocks, or any deleted data. Neutral `profile_
  # unavailable`/`not_suspended` responses keep cross-brand and state details
  # undisclosed.
  class ReinstateProfile
    def self.call(admin_user:, brand:, profile_public_id:)
      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      enforcement = nil
      ActiveRecord::Base.transaction do
        enforcement = AccountEnforcement.active.lock.find_by(brand:, user_id: profile.user_id)
        raise ModerationError, :not_suspended if enforcement.blank?

        membership = BrandMembership.lock.find(enforcement.brand_membership_id)
        membership.update!(status: :active) if membership.suspended?
        enforcement.update!(reverted_at: Time.current, reverted_by: admin_user)
        EnforcementAudit.record(
          admin_user:, enforcement:, event_type: "admin.account_reinstated", severity: :info
        )
      end
      enforcement
    end
  end
end
