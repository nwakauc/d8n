module Community
  class Submissions
    ANSWER_WINDOW = 7.days

    def self.question!(profile:, brand:, attributes:)
      ensure_tenant!(profile:, brand:)
      CommunityQuestion.create!(brand:, author_profile: profile, category: attributes.fetch(:category),
        body: attributes.fetch(:body).to_s.strip, anonymous: attributes.fetch(:anonymous, true), closes_at: ANSWER_WINDOW.from_now)
    end

    def self.answer!(profile:, question:, attributes:)
      raise Access::Unavailable unless question.status_approved? && question.deleted_at.nil? && question.closes_at.future?
      ensure_tenant!(profile:, brand: question.brand)

      CommunityAnswer.create!(brand: question.brand, community_question: question, author_profile: profile,
        body: attributes.fetch(:body).to_s.strip, anonymous: attributes.fetch(:anonymous, false))
    end

    def self.event!(profile:, brand:, attributes:)
      ensure_tenant!(profile:, brand:)
      CommunityEvent.create!(brand:, organizer_profile: profile, **attributes)
    end

    def self.story!(profile:, brand:, attributes:)
      ensure_tenant!(profile:, brand:)
      CommunityStory.create!(brand:, author_profile: profile, **attributes)
    end

    def self.circle!(profile:, brand:, attributes:)
      ensure_tenant!(profile:, brand:)
      CommunityCircle.create!(brand:, creator_profile: profile, **attributes)
    end

    def self.update!(record:, profile:, attributes:)
      Access.owner!(record:, profile:)
      record.assign_attributes(attributes)
      if record.changed? && record.respond_to?(:status_approved?) && record.status_approved?
        record.assign_attributes(
          status: :pending,
          published_at: nil,
          moderation_note: nil,
          reviewed_by_admin_user: nil,
          reviewed_at: nil
        )
      end
      record.save!
      record
    end

    def self.discard!(record:, profile:)
      Access.owner!(record:, profile:)
      record.update!(deleted_at: Time.current)
    end

    def self.ensure_tenant!(profile:, brand:)
      raise Access::Unavailable unless profile.brand_id == brand.id
    end
    private_class_method :ensure_tenant!
  end
end
