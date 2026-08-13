module Trust
  class UnblockProfile
    def self.call(user:, brand:, target_public_id:)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      target = brand.profiles.kept.find_by(public_id: target_public_id)
      return false if target.blank? || target.id == viewer.id

      removed = false
      Profile.transaction do
        locked_ids = Profile.kept.where(brand:, id: [ viewer.id, target.id ]).order(:id).lock.pluck(:id)
        return false unless locked_ids.size == 2

        viewer = Matching::ProfileParticipant.match_member!(user: user.reload, brand:)
        profile_block = ProfileBlock.kept.lock.find_by(brand:, blocker_profile: viewer, blocked_profile: target)
        removed = profile_block.present?
        profile_block&.update!(deleted_at: Time.current)
      end
      removed
    end
  end
end
