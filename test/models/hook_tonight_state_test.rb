require "test_helper"
require_relative "../support/hook_test_helpers"

class HookTonightStateTest < ActiveSupport::TestCase
  include HookTestHelpers

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @profile = create_member(brand: @brand)
  end

  def build_state(expires_at: 2.hours.from_now, deactivated_at: nil)
    HookTonightState.create!(
      brand: @brand, profile: @profile,
      activated_at: Time.current, expires_at:, deactivated_at:
    )
  end

  test "live? and live scope include an active, unexpired, non-deactivated state" do
    state = build_state

    assert state.live?
    assert_includes HookTonightState.live, state
  end

  test "live? and live scope exclude an expired state without any sweeper" do
    state = build_state(expires_at: 1.hour.ago)

    assert_not state.live?
    assert_not_includes HookTonightState.live, state
  end

  test "live? and live scope exclude a manually deactivated state even when unexpired" do
    state = build_state(deactivated_at: Time.current)

    assert_not state.live?
    assert_not_includes HookTonightState.live, state
  end

  test "defaults intent to the policy default" do
    state = HookTonightState.create!(
      brand: @brand, profile: @profile, activated_at: Time.current, expires_at: 2.hours.from_now
    )

    assert_equal HookTonight::Policy::DEFAULT_INTENT, state.intent
  end

  test "rejects an unknown intent" do
    state = HookTonightState.new(
      brand: @brand, profile: @profile, activated_at: Time.current,
      expires_at: 2.hours.from_now, intent: "definitely_not_supported"
    )

    assert_not state.valid?
    assert_includes state.errors.attribute_names, :intent
  end

  test "rejects a profile from another brand" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_member(brand: other_brand)

    state = HookTonightState.new(
      brand: @brand, profile: other_profile, activated_at: Time.current, expires_at: 2.hours.from_now
    )

    assert_not state.valid?
    assert_includes state.errors.attribute_names, :profile
  end

  test "enforces one current-state row per member" do
    build_state

    assert_raises ActiveRecord::RecordNotUnique do
      HookTonightState.create!(
        brand: @brand, profile: @profile, activated_at: Time.current, expires_at: 3.hours.from_now
      )
    end
  end
end
