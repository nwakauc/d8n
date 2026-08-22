module Accounts
  # Brand-level account closure (the user leaves this brand). Synchronous, atomic
  # state transition; the physical media purge is enqueued to run afterwards.
  #
  # In one transaction: tombstone the brand membership (status left + discarded),
  # discard + anonymize the brand profile, end active matches, discard likes/passes,
  # hard-delete precise location history, discard the profile's photos and
  # preferences, and revoke every session for this brand. The user's D8N identity
  # (User, credentials, identity identifiers) is deliberately RETAINED — those are
  # cross-brand; platform-wide identity erasure is a separate future capability.
  # Shared/safety records (conversations, messages, blocks, reports, enforcements,
  # security events) are retained. Idempotent per membership.
  class CloseAccount
    Result = Data.define(:closure, :already_closed)

    def self.call(user:, brand:)
      membership = BrandMembership.kept.find_by(user:, brand:)
      raise ActiveRecord::RecordNotFound, "no active membership" if membership.blank?

      closure = nil
      already = false
      ActiveRecord::Base.transaction do
        membership.lock!
        existing = AccountClosure.find_by(brand_membership_id: membership.id)
        if existing.present?
          closure = existing
          already = true
          next
        end

        profile = brand.profiles.kept.lock.find_by(user:)
        close_profile!(profile) if profile.present?
        revoke_sessions(user:, brand:)
        revoke_devices(user:, brand:, now: Time.current)
        # Tombstone brand participation via `left` (not soft-delete): every auth and
        # product surface already gates on `BrandMembership.kept.active`, so `left`
        # fully removes access while keeping the row findable for idempotency.
        membership.update!(status: :left)
        closure = AccountClosure.create!(
          brand:, user:, brand_membership: membership, profile:, media_purge_state: :pending
        )
        record_event(brand:, user:, membership:, profile:)
      end

      Media::PurgeProfileMediaJob.perform_later(closure.id) unless already
      Result.new(closure:, already_closed: already)
    end

    def self.close_profile!(profile)
      now = Time.current
      end_active_matches(profile:, now:)
      discard_interactions(profile:, now:)
      ProfilePhoto.kept.where(profile:).update_all(
        deleted_at: now, visibility: ProfilePhoto.visibilities.fetch("hidden"), updated_at: now
      )
      ProfilePreference.kept.where(profile:).update_all(deleted_at: now, updated_at: now)
      # Precise location history is sensitive and never needed after closure — hard delete.
      ProfileLocation.where(profile:).delete_all
      # Discard + minimize retained personal data on the tombstoned profile.
      profile.update!(deleted_at: now, visibility: :hidden, display_name: nil, bio: nil)
    end
    private_class_method :close_profile!

    def self.end_active_matches(profile:, now:)
      Match.kept.status_active
        .where("profile_a_id = :id OR profile_b_id = :id", id: profile.id)
        .update_all(status: Match.statuses.fetch("ended"), updated_at: now)
    end
    private_class_method :end_active_matches

    def self.discard_interactions(profile:, now:)
      Like.kept.where(brand_id: profile.brand_id)
        .where("liker_profile_id = :id OR liked_profile_id = :id", id: profile.id)
        .update_all(deleted_at: now, updated_at: now)
      ProfilePass.kept.where(brand_id: profile.brand_id)
        .where("passer_profile_id = :id OR passed_profile_id = :id", id: profile.id)
        .update_all(deleted_at: now, updated_at: now)
    end
    private_class_method :discard_interactions

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

    def self.record_event(brand:, user:, membership:, profile:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "account.closed", severity: :warning,
        metadata: { brand_membership_id: membership.id, profile_id: profile&.id }
      )
    end
    private_class_method :record_event
  end
end
