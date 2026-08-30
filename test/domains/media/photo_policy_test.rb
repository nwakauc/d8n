require "test_helper"

module Media
  class PhotoPolicyTest < ActiveSupport::TestCase
    test "HookUs photos are visible immediately, still pending moderation" do
      brand = Brand.new(slug: "hookus", name: "HookUs")

      state = PhotoPolicy.initial_state(brand:)

      assert_equal :visible, state.visibility
      assert_equal :pending_review, state.status
    end

    test "DateZA photos are visible immediately, still pending moderation" do
      brand = Brand.new(slug: "dateza", name: "DateZA")

      state = PhotoPolicy.initial_state(brand:)

      assert_equal :visible, state.visibility
      assert_equal :pending_review, state.status
      assert_not PhotoPolicy.moderate_first?(brand:)
    end

    test "brands without an explicit policy stay moderate-first (hidden)" do
      %w[date9ja some-future-brand].each do |slug|
        brand = Brand.new(slug:, name: slug)

        state = PhotoPolicy.initial_state(brand:)

        assert_equal :hidden, state.visibility, "#{slug} must default to hidden"
        assert_equal :pending_review, state.status
      end
    end

    test "moderation capability is preserved — no policy grants approved status" do
      # Immediate visibility must not fabricate a moderation decision.
      assert_equal :pending_review, PhotoPolicy::IMMEDIATE.status
      assert_equal :pending_review, PhotoPolicy::MODERATE_FIRST.status
    end

    test "registered brands expose the shared configured maximum" do
      assert_equal 6, PhotoPolicy.max_count(brand: Brand.new(slug: "hookus", name: "HookUs"))
      assert_equal 6, PhotoPolicy.max_count(brand: Brand.new(slug: "dateza", name: "DateZA"))
      assert_equal 6, PhotoPolicy.max_count(brand: Brand.new(slug: "future", name: "Future"))
    end
  end
end
