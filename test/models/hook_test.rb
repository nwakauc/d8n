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

  test "a curated opener's message must match the catalog entry it references" do
    opener = @brand.profile_openers.create!(key: "test_opener", text: "What's your favorite trip so far?", position: 0)

    hook = Hook.new(
      brand: @brand, sender_profile: @sender, recipient_profile: @recipient,
      message: opener.text, profile_opener: opener
    )
    assert hook.valid?

    hook.message = "some other tampered text"
    assert_not hook.valid?
    assert_includes hook.errors[:message], "must match the selected opener"
  end

  test "a freeform (no catalog) hook does not require a profile_opener" do
    hook = Hook.new(brand: @brand, sender_profile: @sender, recipient_profile: @recipient, message: "hi there")

    assert hook.valid?
    assert_nil hook.profile_opener
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
