module Trust
  class BlockProfile
    Result = Data.define(:profile_block, :created)

    def self.call(user:, brand:, target_public_id:)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      target = brand.profiles.kept.find_by(public_id: target_public_id)
      raise AccessError, :profile_unavailable if target.blank? || target.id == viewer.id

      result = nil
      Profile.transaction do
        lock_profiles!(brand:, viewer:, target:)
        viewer = Matching::ProfileParticipant.match_member!(user: user.reload, brand:)
        target.reload
        profile_block = ProfileBlock.kept.find_by(brand:, blocker_profile: viewer, blocked_profile: target)
        created = profile_block.blank?
        profile_block ||= ProfileBlock.create!(brand:, blocker_profile: viewer, blocked_profile: target)
        remove_positive_relationships!(brand:, viewer:, target:)
        result = Result.new(profile_block:, created:)
      end
      result
    end

    def self.lock_profiles!(brand:, viewer:, target:)
      locked_ids = Profile.kept.where(brand:, id: [ viewer.id, target.id ]).order(:id).lock.pluck(:id)
      raise AccessError, :profile_unavailable unless locked_ids.size == 2
    end
    private_class_method :lock_profiles!

    def self.remove_positive_relationships!(brand:, viewer:, target:)
      now = Time.current
      Like.kept.where(brand:).where(
        liker_profile_id: [ viewer.id, target.id ],
        liked_profile_id: [ viewer.id, target.id ]
      ).update_all(deleted_at: now, updated_at: now)

      profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, target.id)
      Match.kept.status_active.where(brand:, profile_a_id:, profile_b_id:)
        .update_all(status: Match.statuses.fetch("ended"), updated_at: now)
    end
    private_class_method :remove_positive_relationships!
  end
end
