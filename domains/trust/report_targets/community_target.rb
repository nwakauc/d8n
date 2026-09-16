module Trust
  module ReportTargets
    # Resolves only Community content that the reporting member can currently
    # see. Public submissions must be approved; Circle discussion additionally
    # requires active Circle membership. Evidence is a bounded immutable content
    # snapshot and never contains moderator notes or private profile data.
    module CommunityTarget
      TYPES = {
        "community_question" => [ CommunityQuestion, :author_profile ],
        "community_answer" => [ CommunityAnswer, :author_profile ],
        "community_event" => [ CommunityEvent, :organizer_profile ],
        "community_story" => [ CommunityStory, :author_profile ],
        "community_circle" => [ CommunityCircle, :creator_profile ],
        "community_post" => [ CommunityPost, :author_profile ],
        "community_comment" => [ CommunityComment, :author_profile ]
      }.freeze

      Resolver = Data.define(:target_type) do
        def resolve(brand:, viewer:, target_public_id:)
          CommunityTarget.resolve(target_type:, brand:, viewer:, target_public_id:)
        end
      end

      module_function

      def for(target_type)
        raise ArgumentError, "unknown Community report target" unless TYPES.key?(target_type)

        Resolver.new(target_type)
      end

      def resolve(target_type:, brand:, viewer:, target_public_id:)
        model, owner_association = TYPES.fetch(target_type)
        scope = %w[community_post community_comment].include?(target_type) ? model.kept : model.published
        record = scope.where(brand:).find_by(public_id: target_public_id)
        raise AccessError, :target_unavailable unless visible?(record:, target_type:, viewer:)

        owner = record.public_send(owner_association)
        raise AccessError, :target_unavailable if owner.blank? || owner.id == viewer.id

        Resolution.new(
          target_type:,
          target_id: record.id,
          reported_profile: owner,
          evidence: evidence(record:, target_type:)
        )
      end

      def visible?(record:, target_type:, viewer:)
        return false if record.blank?

        case target_type
        when "community_answer"
          record.community_question.status_approved? && record.community_question.published_at.present? &&
            record.community_question.deleted_at.nil?
        when "community_post", "community_comment"
          circle = target_type == "community_post" ? record.community_circle : record.community_post.community_circle
          circle.status_approved? && circle.published_at.present? && circle.deleted_at.nil? &&
            CommunityCircleMembership.kept.status_active.exists?(community_circle: circle, profile: viewer)
        else
          record.status_approved?
        end
      end

      def evidence(record:, target_type:)
        payload = {
          "community_type" => target_type,
          "community_public_id" => record.public_id,
          "content_created_at" => record.created_at.iso8601
        }
        payload["title"] = record.title.to_s.first(160) if record.respond_to?(:title)
        payload["body"] = record.body.to_s.first(4_000) if record.respond_to?(:body)
        payload["name"] = record.name.to_s.first(100) if record.respond_to?(:name)
        payload
      end
    end
  end
end
