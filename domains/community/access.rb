module Community
  class Access
    class Unavailable < StandardError; end

    def self.member!(user:, brand:)
      Matching::ProfileParticipant.match_member!(user:, brand:)
    rescue Matching::InteractionError
      raise Unavailable
    end

    def self.owner_or_published!(record:, profile:)
      return record if record.deleted_at.nil? && record.respond_to?(:status_approved?) && record.status_approved?
      return record if record.deleted_at.nil? && owner_profile_id(record) == profile.id

      raise Unavailable
    end

    def self.owner!(record:, profile:)
      return record if record.deleted_at.nil? && owner_profile_id(record) == profile.id

      raise Unavailable
    end

    def self.circle_member!(circle:, profile:)
      raise Unavailable unless circle.deleted_at.nil? && circle.status_approved? && circle.published_at.present?

      membership = CommunityCircleMembership.kept.status_active.find_by(community_circle: circle, profile:)
      raise Unavailable unless membership

      membership
    end

    def self.event_organizer!(event:, profile:)
      return event if event.deleted_at.nil? && event.organizer_profile_id == profile.id

      raise Unavailable
    end

    def self.owner_profile_id(record)
      record.try(:author_profile_id) || record.try(:organizer_profile_id) || record.try(:creator_profile_id)
    end
    private_class_method :owner_profile_id
  end
end
