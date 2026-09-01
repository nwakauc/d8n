module Hq
  module Metrics
    # Shared, brand-scoped metric computations. Controllers and legacy
    # Hq::Analytics::Overview should call into this layer instead of duplicating SQL.
    class Compute
      def self.call(brand:, now: Time.current)
        new(brand:, now:).call
      end

      def initialize(brand:, now:)
        @brand = brand
        @now = now
        @windows = Windows.build(now:)
      end

      def call
        {
          brand: brand.slug,
          generated_at: now,
          time_zone: Windows::TIME_ZONE,
          windows: Windows.new(now:).metadata(@windows),
          audience: audience_section,
          activity: activity_section,
          profile_health: profile_health_section,
          marketplace: marketplace_section,
          trust_safety: trust_safety_section
        }
      end

      attr_reader :brand, :now, :windows

      def audience_section
        meta = Catalog.fetch("memberships.total")
        total = BrandMembership.kept.where(brand:).distinct.count(:user_id)

        {
          memberships_total: MetricValue.available(
            metric_id: "memberships.total",
            definition: meta[:definition],
            version: meta[:version],
            unit: meta[:unit],
            value: total
          ).to_h,
          memberships_new: windowed_metric("memberships.new") { |window| new_memberships(window) }
        }
      end

      def activity_section
        {
          active_users: windowed_metric("users.active") { |window| active_users(window) }
        }
      end

      def profile_health_section
        status_counts = Profile.kept.where(brand:).group(:status).count
        by_status = Profile.statuses.keys.index_with do |key|
          status_counts.fetch(Profile.statuses.fetch(key)) { status_counts.fetch(key, 0) }
        end
        published = Profile.kept.where(brand:, status: :active, visibility: :visible).count
        memberships = BrandMembership.kept.where(brand:).distinct.count(:user_id)
        activation_meta = Catalog.fetch("profiles.activation_ratio")

        activation =
          if memberships.zero?
            MetricValue.insufficient_data(
              metric_id: "profiles.activation_ratio",
              definition: activation_meta[:definition],
              version: activation_meta[:version],
              limitations: [ "No kept memberships on this brand." ]
            )
          else
            MetricValue.available(
              metric_id: "profiles.activation_ratio",
              definition: activation_meta[:definition],
              version: activation_meta[:version],
              unit: activation_meta[:unit],
              value: (by_status.fetch("active", 0).to_f / memberships).round(4),
              numerator: by_status.fetch("active", 0),
              denominator: memberships
            )
          end

        status_meta = Catalog.fetch("profiles.by_status")
        published_meta = Catalog.fetch("profiles.visible_published")

        {
          by_status: MetricValue.available(
            metric_id: "profiles.by_status",
            definition: status_meta[:definition],
            version: status_meta[:version],
            unit: status_meta[:unit],
            value: by_status
          ).to_h,
          visible_published: MetricValue.available(
            metric_id: "profiles.visible_published",
            definition: published_meta[:definition],
            version: published_meta[:version],
            unit: published_meta[:unit],
            value: published
          ).to_h,
          activation_ratio: activation.to_h
        }
      end

      def marketplace_section
        published_scope = Profile.kept.where(brand:, status: :active, visibility: :visible)
        without_likes = published_without_engagement(published_scope, :likes)
        without_matches = published_without_engagement(published_scope, :matches)

        {
          likes_created: windowed_metric("marketplace.likes_created") { |window| likes_created(window) },
          matches_created: windowed_metric("marketplace.matches_created") { |window| matches_created(window) },
          conversations_created: windowed_metric("marketplace.conversations_created") { |window| conversations_created(window) },
          zero_discovery_allocations: discovery_windows,
          published_without_likes: point_metric("marketplace.published_without_likes", without_likes),
          published_without_matches: point_metric("marketplace.published_without_matches", without_matches),
          time_to_first_like_median: deferred_time_to_first("marketplace.time_to_first_like_median"),
          time_to_first_match_median: deferred_time_to_first("marketplace.time_to_first_match_median"),
          time_to_first_conversation_median: deferred_time_to_first("marketplace.time_to_first_conversation_median")
        }
      end

      def trust_safety_section
        reports = Report.where(brand:)
        oldest_open = reports.status_open.minimum(:created_at)
        oldest_age = oldest_open.present? ? [ (now - oldest_open).to_i, 0 ].max : nil

        {
          open_reports: point_metric("trust.open_reports", reports.status_open.count),
          awaiting_decision: point_metric("trust.awaiting_decision", reports.where(status: %i[open reviewing]).count),
          active_enforcements: point_metric("trust.active_enforcements", AccountEnforcement.active.where(brand:).count),
          pending_photo_reviews: point_metric(
            "trust.pending_photo_reviews",
            ProfilePhoto.kept.where(brand:, status: :pending_review).count
          ),
          oldest_open_report_age_seconds: oldest_open_metric(oldest_age)
        }
      end

      def windowed_metric(metric_id)
        meta = Catalog.fetch(metric_id)
        windows.transform_values do |window|
          MetricValue.available(
            metric_id:,
            definition: meta[:definition],
            version: meta[:version],
            unit: meta[:unit],
            value: yield(window)
          ).to_h
        end
      end

      def point_metric(metric_id, value)
        meta = Catalog.fetch(metric_id)
        MetricValue.available(
          metric_id:,
          definition: meta[:definition],
          version: meta[:version],
          unit: meta[:unit],
          value:
        ).to_h
      end

      def oldest_open_metric(value)
        meta = Catalog.fetch("trust.oldest_open_report_age_seconds")
        if value.nil?
          MetricValue.insufficient_data(
            metric_id: "trust.oldest_open_report_age_seconds",
            definition: meta[:definition],
            version: meta[:version],
            limitations: [ "No open reports on this brand." ]
          ).to_h
        else
          MetricValue.available(
            metric_id: "trust.oldest_open_report_age_seconds",
            definition: meta[:definition],
            version: meta[:version],
            unit: meta[:unit],
            value:
          ).to_h
        end
      end

      def deferred_time_to_first(metric_id)
        meta = Catalog.fetch(metric_id)
        MetricValue.unavailable(
          metric_id:,
          definition: meta[:definition],
          version: meta[:version],
          limitations: [
            "Deferred in this milestone to avoid synchronous cross-table medians over large brands.",
            "Requires a bounded rollup job before Command Centre can show this safely."
          ]
        ).to_h
      end

      def new_memberships(window)
        BrandMembership.kept.where(brand:, created_at: utc_range(window)).count
      end

      def active_users(window)
        Session.where(brand:, last_used_at: utc_range(window)).distinct.count(:user_id)
      end

      def likes_created(window)
        Like.kept.where(brand:, created_at: utc_range(window)).count
      end

      def matches_created(window)
        Match.kept.where(brand:, created_at: utc_range(window)).count
      end

      def conversations_created(window)
        Conversation.kept.where(brand:, created_at: utc_range(window)).count
      end

      def discovery_windows
        meta = Catalog.fetch("marketplace.zero_discovery_allocations")
        {
          yesterday: allocation_zero_metric(meta, windows.fetch(:yesterday)),
          last_7d: allocation_zero_metric(meta, windows.fetch(:last_7d)),
          last_30d: allocation_zero_metric(meta, windows.fetch(:last_30d))
        }
      end

      def allocation_zero_metric(meta, window)
        date_range = allocation_date_range(window)
        count = zero_discovery_count(date_range)
        MetricValue.available(
          metric_id: "marketplace.zero_discovery_allocations",
          definition: meta[:definition],
          version: meta[:version],
          unit: meta[:unit],
          value: count
        ).to_h
      end

      def zero_discovery_count(date_range)
        DiscoveryAllocation.kept
          .where(brand:, allocation_date: date_range)
          .left_outer_joins(:allocation_candidates)
          .group("discovery_allocations.id")
          .having("COUNT(discovery_allocation_candidates.id) = 0")
          .count
          .size
      end

      def published_without_engagement(published_scope, kind)
        case kind
        when :likes
          published_scope
            .where.not(id: Like.kept.where(brand:).select(:liker_profile_id))
            .where.not(id: Like.kept.where(brand:).select(:liked_profile_id))
            .count
        when :matches
          published_scope
            .where.not(id: Match.kept.where(brand:).select(:profile_a_id))
            .where.not(id: Match.kept.where(brand:).select(:profile_b_id))
            .count
        else
          raise ArgumentError, "unsupported engagement kind: #{kind.inspect}"
        end
      end

      def utc_range(window)
        window.start_at.utc...window.end_at.utc
      end

      def allocation_date_range(window)
        start_date = window.start_at.in_time_zone(Windows::TIME_ZONE).to_date
        end_date = window.end_at.in_time_zone(Windows::TIME_ZONE).to_date
        start_date...end_date
      end
    end
  end
end
