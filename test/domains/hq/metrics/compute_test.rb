require "test_helper"

module Hq
  module Metrics
    class ComputeTest < ActiveSupport::TestCase
      test "computes brand-scoped audience, profile, and marketplace metrics" do
        brand = Brand.create!(slug: "metrics-brand", name: "Metrics Brand")
        other_brand = Brand.create!(slug: "metrics-other", name: "Metrics Other")
        now = Time.utc(2026, 8, 30, 10, 0, 0)

        published = create_profile(brand:, name: "Published")
        draft = create_profile(brand:, name: "Draft", status: :draft)
        other = create_profile(brand: other_brand, name: "Other")

        membership = published.brand_membership
        membership.update_columns(created_at: now - 2.days)
        draft.brand_membership.update_columns(created_at: now - 2.days)
        other.brand_membership.update_columns(created_at: now - 2.days)
        Session.issue!(user: published.user, brand:).last.update_columns(last_used_at: now - 1.hour)

        like = Like.create!(brand:, liker_profile: published, liked_profile: draft)
        like.update_columns(created_at: now - 1.hour)

        result = Compute.call(brand:, now:)

        assert_equal 2, result.dig(:audience, :memberships_total, :value)
        assert_equal 2, result.dig(:audience, :memberships_new, :last_7d, :value)
        assert_equal 1, result.dig(:activity, :active_users, :today, :value)
        assert_equal 1, result.dig(:profile_health, :visible_published, :value)
        assert_equal 1, result.dig(:profile_health, :by_status, :value, "active")
        assert_equal 1, result.dig(:profile_health, :by_status, :value, "draft")
        assert_equal 1, result.dig(:marketplace, :likes_created, :today, :value)
        assert_equal 0, result.dig(:marketplace, :published_without_likes, :value)
        assert_equal 1, result.dig(:marketplace, :published_without_matches, :value)
        assert_equal "unavailable", result.dig(:marketplace, :time_to_first_like_median, :status)
      end

      test "returns insufficient data for activation and oldest report when empty" do
        brand = Brand.create!(slug: "metrics-empty", name: "Metrics Empty")

        result = Compute.call(brand:, now: Time.utc(2026, 8, 30, 10, 0, 0))

        assert_equal "insufficient_data", result.dig(:profile_health, :activation_ratio, :status)
        assert_equal "insufficient_data", result.dig(:trust_safety, :oldest_open_report_age_seconds, :status)
        assert_equal 0, result.dig(:trust_safety, :open_reports, :value)
      end

      test "uses non-overlapping local calendar dates for discovery windows" do
        now = Time.utc(2026, 8, 30, 10, 0, 0)
        windows = Windows.build(now:)

        assert_equal Date.new(2026, 8, 29), windows.fetch(:yesterday).start_at.to_date
        assert_equal Date.new(2026, 8, 30), windows.fetch(:yesterday).end_at.to_date
        assert_equal Date.new(2026, 8, 23), windows.fetch(:last_7d).start_at.to_date
        assert_equal Date.new(2026, 8, 30), windows.fetch(:last_7d).end_at.to_date
      end

      private

      def create_profile(brand:, name:, status: :active)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        Profile.create!(
          brand:, user:, brand_membership: membership, display_name: name,
          birthdate: 30.years.ago.to_date, gender: "person", status:, visibility: :visible
        )
      end
    end
  end
end
