module Community
  class Moderation
    class InvalidTransition < StandardError; end
    Result = Data.define(:record, :transitioned)
    TYPES = { "questions" => CommunityQuestion, "answers" => CommunityAnswer, "events" => CommunityEvent, "stories" => CommunityStory, "circles" => CommunityCircle }.freeze
    PRELOADS = {
      "questions" => [ :selected_answer, { author_profile: %i[user brand_membership] } ],
      "answers" => [ :community_question, { author_profile: %i[user brand_membership] } ],
      "events" => [ :community_event_rsvps ],
      "stories" => [ { author_profile: %i[user brand_membership] } ],
      "circles" => [ :community_circle_memberships ]
    }.freeze

    def self.queue(type:, brand:, limit: 100)
      model = TYPES.fetch(type.to_s)
      model.kept.where(brand:, status: :pending).includes(*PRELOADS.fetch(type.to_s))
        .order(:created_at, :id).limit(limit)
    end

    def self.transition!(type:, public_id:, brand:, admin:, status:, note: nil)
      model = TYPES.fetch(type.to_s)
      record = model.kept.where(brand:).find_by!(public_id:)
      target = status.to_s
      raise InvalidTransition unless %w[approved rejected hidden].include?(target)

      transitioned = false
      model.transaction do
        record.lock!
        unless record.status == target
          record.update!(
            status: target,
            moderation_note: note.to_s.strip.presence,
            reviewed_by_admin_user: admin,
            reviewed_at: Time.current,
            published_at: target == "approved" ? Time.current : nil
          )
          audit!(record:, type: type.to_s, brand:, admin:, status: target, has_note: note.present?)
          transitioned = true
        end
      end

      Result.new(record:, transitioned:)
    end


    def self.audit!(record:, type:, brand:, admin:, status:, has_note:)
      SecurityEvent.create!(
        brand:,
        user: admin.user,
        event_type: "admin.community_moderated",
        severity: status == "approved" ? :info : :warning,
        metadata: {
          admin_user_id: admin.id,
          community_type: type,
          community_public_id: record.public_id,
          decision: status,
          has_note:
        }
      )
    end
    private_class_method :audit!
  end
end
