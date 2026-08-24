module Matching
  module Find
    class Search
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 10

      class ViewerIneligible < StandardError; end
      class InvalidLimit < StandardError; end

      Result = Data.define(:profiles, :next_cursor, :allowance, :viewer, :eligibility_policy, :decorators)

      def self.call(user:, brand:, cursor: nil, limit: nil, min_age: nil, max_age: nil,
        max_distance_km: nil, relationship_intent: nil, now: Time.current)
        new(
          user:, brand:, cursor:, limit:, min_age:, max_age:,
          max_distance_km:, relationship_intent:, now:
        ).call
      end

      def initialize(user:, brand:, cursor:, limit:, min_age:, max_age:, max_distance_km:,
        relationship_intent:, now:)
        @user = user
        @brand = brand
        @cursor = cursor
        @limit = normalize_limit(limit)
        @surface = PolicyRegistry.surface_for(brand:)
        @policy = surface.policy
        @filter = Filter.parse(brand:, min_age:, max_age:, max_distance_km:, relationship_intent:)
        @now = now
      end

      def call
        membership = BrandMembership.kept.active.find_by(user:, brand:)
        raise ViewerIneligible if membership.blank?

        result = nil
        BrandMembership.transaction do
          membership.lock!
          viewer = current_viewer!
          result = allocate_page(viewer:, membership:)
        end
        result
      end

      private

      attr_reader :user, :brand, :cursor, :limit, :surface, :policy, :filter, :now

      def current_viewer!
        ProfileParticipant.discoverable!(user:, brand:)
      rescue InteractionError
        raise ViewerIneligible
      end

      def allocate_page(viewer:, membership:)
        exposure_date = policy.date_at(now)
        ledger = FindProfileExposure.where(brand:, brand_membership: membership, exposure_date:)
        daily_limit = policy.daily_limit(membership)
        used = ledger.count
        remaining = [ daily_limit - used, 0 ].max

        candidates = candidate_scope(viewer:, membership:).limit(limit + 1).to_a
        page = candidates.first(limit)
        exposed_candidate_ids = ledger.where(candidate_profile_id: page.map(&:id)).pluck(:candidate_profile_id).to_set
        selected = []

        page.each do |candidate|
          if exposed_candidate_ids.include?(candidate.id)
            selected << candidate
          elsif remaining.positive?
            record_exposure!(membership:, viewer:, candidate:, exposure_date:)
            selected << candidate
            remaining -= 1
            used += 1
          end
        end

        exhausted = used >= daily_limit
        next_cursor = if !exhausted && candidates.length > limit && selected.any?
          Cursor.encode(brand:, membership:, policy:, filter:, profile: selected.last)
        end

        Result.new(
          profiles: selected,
          next_cursor:,
          allowance: {
            limit: daily_limit,
            used:,
            remaining: [ daily_limit - used, 0 ].max,
            exhausted:,
            resets_at: policy.resets_at(now).iso8601
          },
          viewer:,
          eligibility_policy: surface.eligibility_policy,
          decorators: surface.decorators
        )
      end

      def candidate_scope(viewer:, membership:)
        scope = EligibilityScope.call(brand:, viewer:, policy: surface.eligibility_policy)
        scope = ExclusionsScope.call(scope:, viewer:, contributors: surface.exclusions)
        scope = Filter.apply(scope:, brand:, viewer:, eligibility_policy: surface.eligibility_policy, filter:)
        scope = policy.rank(scope)
        scope = Cursor.apply(scope:, value: cursor, brand:, membership:, policy:, filter:)
        scope.includes(
          :brand,
          { profile_option_selections: [ :profile_option, :profile_option_group ] },
          { profile_photos: { display_image_attachment: :blob } }
        )
      end

      def record_exposure!(membership:, viewer:, candidate:, exposure_date:)
        FindProfileExposure.create!(
          brand:, user:, brand_membership: membership, viewer_profile: viewer,
          candidate_profile: candidate, exposure_date:
        )
      end

      def normalize_limit(value)
        return DEFAULT_LIMIT if value.blank?

        parsed = Integer(value.to_s, 10)
        raise InvalidLimit unless parsed.between?(1, MAX_LIMIT)

        parsed
      rescue ArgumentError, TypeError
        raise InvalidLimit
      end
    end
  end
end
