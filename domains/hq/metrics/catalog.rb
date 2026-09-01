module Hq
  module Metrics
    # Canonical metric metadata. Computation lives in domain services; this is the
    # single definition source for API responses and future registry expansion.
    module Catalog
      DEFINITIONS = {
        "memberships.total" => {
          version: 1,
          definition: "Distinct users with a kept BrandMembership on the brand.",
          unit: "count"
        },
        "memberships.new" => {
          version: 1,
          definition: "Kept BrandMembership rows created in the window.",
          unit: "count"
        },
        "users.active" => {
          version: 1,
          definition: "Distinct users with a Session last_used_at in the window for the brand.",
          unit: "count"
        },
        "profiles.by_status" => {
          version: 1,
          definition: "Kept profiles grouped by profile status at snapshot time.",
          unit: "count"
        },
        "profiles.visible_published" => {
          version: 1,
          definition: "Kept profiles with status active and visibility visible.",
          unit: "count"
        },
        "profiles.activation_ratio" => {
          version: 1,
          definition: "Active profiles divided by kept memberships (usable profile rate).",
          unit: "ratio"
        },
        "marketplace.likes_created" => {
          version: 1,
          definition: "Kept Like rows created in the window.",
          unit: "count"
        },
        "marketplace.matches_created" => {
          version: 1,
          definition: "Kept Match rows created in the window.",
          unit: "count"
        },
        "marketplace.conversations_created" => {
          version: 1,
          definition: "Kept Conversation rows created in the window.",
          unit: "count"
        },
        "marketplace.zero_discovery_allocations" => {
          version: 1,
          definition: "DiscoveryAllocation rows on completed local calendar dates in the window with zero kept candidates.",
          unit: "count"
        },
        "marketplace.published_without_likes" => {
          version: 1,
          definition: "Published profiles with no kept Like row as liker or liked profile (lifetime).",
          unit: "count"
        },
        "marketplace.published_without_matches" => {
          version: 1,
          definition: "Published profiles with no kept Match row on either profile side (lifetime).",
          unit: "count"
        },
        "marketplace.time_to_first_like_median" => {
          version: 1,
          definition: "Median seconds from profile creation to first kept like sent by the member.",
          unit: "seconds"
        },
        "marketplace.time_to_first_match_median" => {
          version: 1,
          definition: "Median seconds from profile creation to first kept match involving the member.",
          unit: "seconds"
        },
        "marketplace.time_to_first_conversation_median" => {
          version: 1,
          definition: "Median seconds from profile creation to first kept conversation involving the member.",
          unit: "seconds"
        },
        "trust.open_reports" => {
          version: 1,
          definition: "Reports with status open.",
          unit: "count"
        },
        "trust.awaiting_decision" => {
          version: 1,
          definition: "Reports with status open or reviewing.",
          unit: "count"
        },
        "trust.active_enforcements" => {
          version: 1,
          definition: "AccountEnforcement rows active on the brand.",
          unit: "count"
        },
        "trust.pending_photo_reviews" => {
          version: 1,
          definition: "Kept profile photos awaiting moderation review.",
          unit: "count"
        },
        "trust.oldest_open_report_age_seconds" => {
          version: 1,
          definition: "Age in seconds of the oldest open report, if any.",
          unit: "seconds"
        }
      }.freeze

      module_function

      def fetch(metric_id)
        DEFINITIONS.fetch(metric_id)
      end
    end
  end
end
