require "test_helper"

class SecurityEventTest < ActiveSupport::TestCase
  test "can record platform-level event without a brand" do
    event = SecurityEvent.create!(event_type: "auth.otp.throttled", severity: :warning)

    assert event.warning?
    assert_nil event.brand
  end

  test "requires event type" do
    event = SecurityEvent.new

    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end
end
