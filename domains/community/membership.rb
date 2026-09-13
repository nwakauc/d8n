module Community
  class Membership
    Result = Data.define(:membership, :created)

    def self.join!(circle:, profile:)
      raise Access::Unavailable unless circle.status_approved? && circle.published_at.present?

      circle.with_lock do
        membership = CommunityCircleMembership.kept.find_or_initialize_by(
          community_circle: circle,
          brand: circle.brand,
          profile:
        )
        created = membership.new_record?
        membership.status = :active
        membership.save!
        Result.new(membership:, created:)
      end
    end

    def self.leave!(circle:, profile:)
      membership = CommunityCircleMembership.kept.find_by(community_circle: circle, brand: circle.brand, profile:)
      membership&.update!(status: :left)
      membership
    end
  end
end
