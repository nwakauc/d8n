module Matching
  class LikeProfile
    Result = Data.define(:like, :match, :created)

    def self.call(user:, brand:, target_public_id:, eligibility_policy: nil)
      new(user:, brand:, target_public_id:, eligibility_policy:).call
    end

    def initialize(user:, brand:, target_public_id:, eligibility_policy:)
      @user = user
      @brand = brand
      @target_public_id = target_public_id
      @eligibility_policy = eligibility_policy
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
        existing = Like.kept.find_by(brand:, liker_profile: viewer, liked_profile: target)
        if existing
          result = Result.new(like: existing, match: active_match(viewer:, target:), created: false)
          next
        end

        ensure_not_matched!(viewer:, target:)
        ProfilePass.kept.find_by(brand:, passer_profile: viewer, passed_profile: target)&.update!(deleted_at: Time.current)
        like = Like.create!(brand:, liker_profile: viewer, liked_profile: target, kind: :like)
        result = Result.new(like:, match: create_match_if_mutual(viewer:, target:), created: true)
      end
      result
    end

    private

    attr_reader :user, :brand, :target_public_id, :eligibility_policy

    def lock_participants!(viewer:, target:)
      locked_ids = Profile.kept.where(brand:, id: [ viewer.id, target.id ]).order(:id).lock.pluck(:id)
      raise InteractionError, :profile_unavailable unless locked_ids.size == 2
    end

    def ensure_target_eligible!(viewer:, target:)
      policy = eligibility_policy || StrategyRegistry.eligibility_policy_for(brand:)
      eligible = EligibilityScope.call(
        brand:, viewer:, policy:
      ).where(id: target.id).exists?
      raise InteractionError, :profile_unavailable unless eligible
    end

    def ensure_not_matched!(viewer:, target:)
      raise InteractionError, :already_matched if active_match(viewer:, target:)
    end

    def create_match_if_mutual(viewer:, target:)
      reverse = Like.kept.exists?(brand:, liker_profile: target, liked_profile: viewer)
      return unless reverse

      profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, target.id)
      Match.kept.status_active.find_or_create_by!(brand:, profile_a_id:, profile_b_id:)
    end

    def active_match(viewer:, target:)
      profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, target.id)
      Match.kept.status_active.find_by(brand:, profile_a_id:, profile_b_id:)
    end
  end
end
