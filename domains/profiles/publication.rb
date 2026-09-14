module Profiles
  class Publication
    class Incomplete < StandardError
      attr_reader :completion

      def initialize(completion)
        @completion = completion
        super("profile is incomplete")
      end
    end

    class Unavailable < StandardError; end

    def self.activate!(user:, brand:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        ensure_account_available!(profile)
        raise Unavailable, "suspended profiles cannot be activated" if profile.suspended?

        completion = Completion.call(profile:)
        raise Incomplete, completion unless completion.complete?

        already_published = profile.active? && profile.visible?
        profile.update!(status: :active, visibility: :visible)
        unless already_published
          Analytics::Emit.call(
            event_type: "profile.published",
            brand:,
            user:,
            profile:,
            occurred_at: profile.updated_at,
            idempotency_key: "profile.published:#{profile.id}:#{profile.updated_at.to_f}"
          )
        end
        award_trust!(profile)
      end

      profile
    end

    def self.deactivate!(user:, brand:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        if profile.suspended?
          profile.update!(visibility: :hidden)
        else
          profile.update!(status: :draft, visibility: :hidden)
        end
      end

      profile
    end

    def self.unpublish_if_incomplete!(profile:)
      return profile unless profile.active?
      return profile if Completion.call(profile:).complete?

      profile.update!(status: :draft, visibility: :hidden)
      profile
    end

    def self.ensure_account_available!(profile)
      user = profile.user
      membership = profile.brand_membership
      return if user.active? && user.deleted_at.nil? && membership.active? && membership.deleted_at.nil?

      raise Unavailable, "profile account is unavailable"
    end
    private_class_method :ensure_account_available!

    # Live trust award (ADR 0025 / Trust::Date9jaSchedule) — identical points
    # to Date9ja's own award_profile_completion!/award_compatibility_completion!.
    # Date9ja tracks these as two separate onboarding facts; D8N's single
    # Completion gate already requires both a complete profile AND the
    # compatibility-equivalent option groups (Profiles::Date9jaProfileCatalog's
    # REQUIRED_OPTION_GROUPS) to pass, so both facts are simultaneously true
    # the moment activate! succeeds — a member earns the same combined total
    # (110 + 40) a fully-onboarded Date9ja member would have. Idempotent per
    # user, so calling this on every republish still awards each exactly once.
    def self.award_trust!(profile)
      Trust::AwardEvent.call(
        user: profile.user, brand: profile.brand, profile:,
        event_type: "profile_completed", points: Trust::Date9jaSchedule::PROFILE_COMPLETED_POINTS,
        idempotency_key: "activity:#{profile.user_id}:profile_completed", source: profile
      )
      Trust::AwardEvent.call(
        user: profile.user, brand: profile.brand, profile:,
        event_type: "compatibility_completed", points: Trust::Date9jaSchedule::COMPATIBILITY_COMPLETED_POINTS,
        idempotency_key: "activity:#{profile.user_id}:compatibility_completed", source: profile
      )
    end
    private_class_method :award_trust!
  end
end
