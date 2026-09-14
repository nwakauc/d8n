module Trust
  # Daily longevity awards (ADR 0025 / Trust::Date9jaSchedule) — identical
  # milestones to Date9ja's own TrustScoreMembershipMilestonesJob. Idempotent
  # per user/milestone/brand, so running daily (rather than exactly on the
  # anniversary) is safe: once a milestone's key exists it never awards again.
  class AwardMembershipMilestonesJob < ApplicationJob
    queue_as :default

    def perform
      Brand.find_each do |brand|
        Profile.kept.where(brand:).find_each do |profile|
          award_due_milestones(profile)
        end
      end
    end

    private

    def award_due_milestones(profile)
      Date9jaSchedule::MEMBERSHIP_MILESTONES.each do |milestone|
        next unless profile.created_at <= milestone.fetch(:duration).ago

        AwardEvent.call(
          user: profile.user, brand: profile.brand, profile:,
          event_type: "membership_#{milestone.fetch(:key)}", points: milestone.fetch(:points),
          idempotency_key: "membership:#{profile.user_id}:#{milestone.fetch(:key)}", source: profile
        )
      end
    end
  end
end
