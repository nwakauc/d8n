require "test_helper"
require_relative "../support/hook_test_helpers"

class HookTest < ActiveSupport::TestCase
  include HookTestHelpers

  setup do
    @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
    @sender = create_member(brand: @brand)
    @recipient = create_member(brand: @brand)
  end

  test "defaults public_id and expires_at on create" do
    hook = Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "hi there")

    assert_match Profile::PUBLIC_ID_FORMAT, hook.public_id
    assert_in_delta Hooks::Policy::EXPIRES_IN.from_now.to_i, hook.expires_at.to_i, 5
    assert hook.status_pending?
    assert hook.live?
  end

  test "rejects a self hook" do
    hook = Hook.new(brand: @brand, sender_profile: @sender, recipient_profile: @sender, message: "hi")

    assert_not hook.valid?
    assert_includes hook.errors[:recipient_profile], "cannot be the sender profile"
  end

  test "rejects a blank or oversized message" do
    assert_not Hook.new(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "").valid?
    too_long = "a" * (Message::MAX_BODY_LENGTH + 1)
    assert_not Hook.new(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: too_long).valid?
  end

  test "enforces one hook per ordered pair at the database" do
    Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "first")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "second")
    end
  end

  test "live scope excludes expired and non-pending hooks" do
    live = Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "live")
    other = create_member(brand: @brand)
    expired = Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: other, message: "old",
      expires_at: 1.hour.ago)
    third = create_member(brand: @brand)
    accepted = Hook.create!(brand: @brand, sender_profile: @sender, recipient_profile: third, message: "done",
      status: :accepted)

    ids = Hook.live.pluck(:id)
    assert_includes ids, live.id
    assert_not_includes ids, expired.id
    assert_not_includes ids, accepted.id
    assert_not expired.live?
    assert_not accepted.live?
  end
end
