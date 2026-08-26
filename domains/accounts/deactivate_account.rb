module Accounts
  # Brand-level, reversible account deactivation (the user steps away without
  # closing the account). Distinct from Admin::SuspendProfile (moderation, tied to
  # an AccountEnforcement) and from CloseAccount (one-way deletion): deactivation
  # touches only the BrandMembership + this brand's sessions/devices. Profile,
  # photos, matches, likes, conversations, location, and preferences are left
  # completely intact so Identity::AccountReactivation can restore full
  # participation with no data loss.
  #
  # `BrandMembership.kept.active` is the shared eligibility predicate every
  # product/auth surface already gates on (Matching::ProfileParticipant,
  # SessionAuthenticator, discovery/find/notifications scopes) — moving status off
  # `active` is therefore sufficient on its own to drop the member out of
  # discovery, find, matching, messaging, and new sessions. No brand-specific or
  # surface-specific filtering is required.
  class DeactivateAccount
    Result = Data.define(:membership, :already_deactivated)

    def self.call(user:, brand:)
      membership = BrandMembership.kept.find_by(user:, brand:)
      raise ActiveRecord::RecordNotFound, "no active membership" if membership.blank?

      already = false
      ActiveRecord::Base.transaction do
        membership.lock!
        if membership.deactivated?
          already = true
          next
        end
        raise AccountLifecycleError, :account_unavailable unless membership.active?

        membership.update!(status: :deactivated)
        revoke_sessions(user:, brand:)
        revoke_devices(user:, brand:, now: Time.current)
        record_event(brand:, user:, membership:)
      end

      Result.new(membership: membership.reload, already_deactivated: already)
    end

    def self.revoke_sessions(user:, brand:)
      Session.active.where(user:, brand:).find_each do |session|
        Identity::SessionRevoker.call(session:)
      end
    end
    private_class_method :revoke_sessions

    def self.revoke_devices(user:, brand:, now:)
      DeviceRegistration.deliverable.where(user:, brand:).update_all(
        enabled: false,
        revoked_at: now,
        updated_at: now
      )
    end
    private_class_method :revoke_devices

    def self.record_event(brand:, user:, membership:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "account.deactivated", severity: :info,
        metadata: { brand_membership_id: membership.id }
      )
    end
    private_class_method :record_event
  end
end
