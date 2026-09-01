module Hq
  module ProductIntelligence
    class Funnel
      Result = Data.define(:brand, :window, :generated_at, :time_zone, :stages)

      def self.call(brand:, window:, now: Time.current)
        new(brand:, window:, now:).call
      end

      def initialize(brand:, window:, now:)
        @brand = brand
        @window_key = window.to_s
        @window = Window.resolve(key: @window_key, now:)
        @now = now
      end

      def call
        memberships = BrandMembership.kept.where(brand:, created_at: utc_range)
        user_ids = memberships.distinct.select(:user_id)
        registered = memberships.distinct.count(:user_id)
        published = published_count(user_ids)
        first_interaction = first_like_count(user_ids)

        Result.new(
          brand: brand.slug,
          window: window_key,
          generated_at: now,
          time_zone: Hq::Metrics::Windows::TIME_ZONE,
          stages: [
            stage("registered", "Kept brand memberships created in the cohort window.", registered, previous: nil, registration: registered),
            unavailable_stage(
              "onboarding_completed",
              "No authoritative onboarding-completed timestamp is persisted yet."
            ),
            stage(
              "profile_published",
              "Members in the registration cohort with a profile.published event in the cohort window.",
              published, previous: registered, registration: registered,
              limitations: [ "Only publications recorded after AnalyticsEvent instrumentation are counted." ]
            ),
            stage(
              "first_like_sent",
              "Members in the registration cohort who sent at least one kept Like in the cohort window.",
              first_interaction, previous: nil, registration: registered
            )
          ]
        )
      end

      private

      attr_reader :brand, :window_key, :window, :now

      def published_count(user_ids)
        AnalyticsEvent.where(
          brand:, event_type: "profile.published", user_id: user_ids, occurred_at: utc_range
        ).distinct.count(:user_id)
      end

      def first_like_count(user_ids)
        Like.kept.where(brand:, created_at: utc_range)
          .joins(:liker_profile)
          .where(profiles: { user_id: user_ids })
          .distinct.count(:user_id)
      end

      def stage(id, definition, value, previous:, registration:, limitations: [])
        {
          id:, definition:, status: "available", value:, unit: "members",
          conversion_from_previous: previous && ratio(value, previous),
          conversion_from_registration: ratio(value, registration), limitations:
        }
      end

      def unavailable_stage(id, limitation)
        { id:, definition: limitation, status: "unavailable", unit: "members", limitations: [ limitation ] }
      end

      def ratio(numerator, denominator)
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator).round(4)
      end

      def utc_range
        window.start_at.utc...window.end_at.utc
      end
    end
  end
end
