module Matching
  class PassProfile
    Result = Data.define(:profile_pass, :created)

    def self.call(user:, brand:, target_public_id:, strategy: nil)
      new(user:, brand:, target_public_id:, strategy:).call
    end

    def initialize(user:, brand:, target_public_id:, strategy:)
      @user = user
      @brand = brand
      @target_public_id = target_public_id
      @strategy = strategy
    end

    def call
      viewer = ProfileParticipant.discoverable!(user:, brand:)
      target = brand.profiles.kept.find_by(public_id: target_public_id)
      raise InteractionError, :profile_unavailable if target.blank? || target.id == viewer.id

      result = nil
      Profile.transaction do
        lock_participants!(viewer:, target:)
        ProfileParticipant.discoverable!(user: user.reload, brand:)
        ensure_target_eligible!(viewer:, target:)
        existing = ProfilePass.kept.find_by(brand:, passer_profile: viewer, passed_profile: target)
        if existing
          result = Result.new(profile_pass: existing, created: false)
          next
        end

        ensure_no_positive_relationship!(viewer:, target:)
        profile_pass = ProfilePass.create!(brand:, passer_profile: viewer, passed_profile: target)
        result = Result.new(profile_pass:, created: true)
      end
      result
    end

    private

    attr_reader :user, :brand, :target_public_id, :strategy

    def lock_participants!(viewer:, target:)
      locked_ids = Profile.kept.where(brand:, id: [ viewer.id, target.id ]).order(:id).lock.pluck(:id)
      raise InteractionError, :profile_unavailable unless locked_ids.size == 2
    end

    def ensure_target_eligible!(viewer:, target:)
      selected_strategy = strategy || StrategyRegistry.fetch(brand:)
      eligible = EligibilityScope.call(
        brand:, viewer:, location_max_age: selected_strategy.location_max_age
      ).where(id: target.id).exists?
      raise InteractionError, :profile_unavailable unless eligible
    end

    def ensure_no_positive_relationship!(viewer:, target:)
      if Like.kept.exists?(brand:, liker_profile: viewer, liked_profile: target)
        raise InteractionError, :already_liked
      end

      profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, target.id)
      if Match.kept.status_active.exists?(brand:, profile_a_id:, profile_b_id:)
        raise InteractionError, :already_matched
      end
    end
  end
end
