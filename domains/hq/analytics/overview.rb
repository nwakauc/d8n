module Hq
  module Analytics
    # Read-only, brand-scoped overview for the Operations dashboard. These
    # metrics deliberately use the canonical current definitions in METRICS.md:
    # registrations come from kept BrandMembership rows and activity comes
    # from distinct users with a Session last used in the requested window.
    class Overview
      TIME_ZONE = "Africa/Johannesburg"

      Result = Data.define(
        :brand, :generated_at, :time_zone,
        :signups_today, :signups_this_week, :signups_this_month,
        :active_today, :active_7d, :active_30d,
        :gender_split, :total_registered_members,
        :realme_distribution, :trust_summary
      )

      def self.call(brand:, now: Time.current)
        new(brand:, now:).call
      end

      def initialize(brand:, now:)
        @brand = brand
        @now = now
        @zone = ActiveSupport::TimeZone[TIME_ZONE]
      end

      def call
        local_now = now.in_time_zone(zone)
        today_start = local_now.beginning_of_day
        week_start = local_now.beginning_of_week(:sunday)
        month_start = local_now.beginning_of_month

        Result.new(
          brand: brand.slug,
          generated_at: now,
          time_zone: TIME_ZONE,
          signups_today: signup_count(today_start),
          signups_this_week: signup_count(week_start),
          signups_this_month: signup_count(month_start),
          active_today: active_count(today_start),
          active_7d: active_count(now - 7.days),
          active_30d: active_count(now - 30.days),
          gender_split: gender_split,
          total_registered_members: BrandMembership.kept.where(brand:).distinct.count(:user_id),
          realme_distribution: realme_distribution,
          trust_summary: trust_summary
        )
      end

      private

      attr_reader :brand, :now, :zone

      # RealMe states are canonical -- Identity::RealmeAssertions::STATUSES and
      # Identity::RealmeBadge already define them; this only counts members
      # into those existing buckets, it does not invent a new taxonomy.
      # Every kept member falls into exactly one bucket.
      def realme_distribution
        member_ids = Profile.kept.where(brand:).distinct.pluck(:user_id)
        return { not_started: 0, pending: 0, messaging_eligible: 0, full_badge: 0, rejected_only: 0 } if member_ids.empty?

        badges = ::Identity::RealmeBadge.bulk(user_ids: member_ids, brand:)
        assertions_by_user = VerificationAssertion.where(brand:, user_id: member_ids)
          .group(:user_id, :status).count

        counts = { not_started: 0, pending: 0, messaging_eligible: 0, full_badge: 0, rejected_only: 0 }
        member_ids.each do |user_id|
          statuses = assertions_by_user.filter_map { |(uid, status), n| status if uid == user_id && n.positive? }
          if badges.fetch(user_id, false)
            counts[:full_badge] += 1
          elsif statuses.empty?
            counts[:not_started] += 1
          elsif statuses.include?("approved")
            counts[:messaging_eligible] += 1
          elsif statuses.include?("pending")
            counts[:pending] += 1
          else
            counts[:rejected_only] += 1
          end
        end
        counts
      end

      # No canonical trust "risk band" exists anywhere in this codebase today
      # (Trust::Ledger exposes only a plain non-negative integer score) --
      # deliberately not inventing one here. Bounded counts/aggregates only.
      def trust_summary
        member_ids = Profile.kept.where(brand:).distinct.pluck(:user_id)
        return { members_scored: 0, average_score: 0, members_with_active_deduction: 0 } if member_ids.empty?

        users_by_id = User.where(id: member_ids).index_by(&:id)
        scores = member_ids.map { |user_id| ::Trust::Ledger.score(user: users_by_id[user_id], brand:) }
        {
          members_scored: member_ids.size,
          average_score: (scores.sum.to_f / member_ids.size).round(1),
          members_with_active_deduction: TrustAdjustment.where(brand:, user_id: member_ids)
            .where.not(appeal_status: :overturned).distinct.count(:user_id)
        }
      end

      def signup_count(start_time)
        BrandMembership.kept.where(brand:, created_at: start_time.utc..now).count
      end

      def active_count(start_time)
        Session.where(brand:, last_used_at: start_time.utc..now).distinct.count(:user_id)
      end

      def gender_split
        counts = Profile.kept.where(brand:).group(:gender).count
        unknown = counts[nil].to_i + counts[""].to_i
        known = counts.except(nil, "", "woman", "man")

        {
          woman: counts["woman"].to_i,
          man: counts["man"].to_i,
          other: known.values.sum,
          unknown:
        }
      end
    end
  end
end
