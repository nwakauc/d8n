require "test_helper"

module Analytics
  class EmitTest < ActiveSupport::TestCase
    test "records an immutable, brand-scoped event and is idempotent" do
      brand = Brand.create!(slug: "events-brand", name: "Events Brand")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      occurred_at = Time.utc(2026, 9, 1, 10, 0, 0)

      first = Emit.call(
        event_type: "member.registered", brand:, user:, occurred_at:,
        idempotency_key: "member.registered:#{membership.id}"
      )
      second = Emit.call(
        event_type: "member.registered", brand:, user:, occurred_at: occurred_at + 1.hour,
        idempotency_key: "member.registered:#{membership.id}"
      )

      assert_equal first.id, second.id
      assert_equal occurred_at, first.occurred_at
      assert_equal brand.id, first.brand_id
      assert_raises(ActiveRecord::ReadOnlyRecord) { first.update!(occurred_at: occurred_at + 1.hour) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { first.destroy! }
    end

    test "rejects unknown event types and uncontrolled properties" do
      brand = Brand.create!(slug: "events-validation", name: "Events Validation")

      assert_raises(Emit::InvalidEvent) do
        Emit.call(event_type: "unknown.event", brand:, properties: {}, idempotency_key: "unknown")
      end
      assert_raises(ActiveRecord::RecordInvalid) do
        AnalyticsEvent.create!(
          event_id: SecureRandom.uuid, event_type: "member.registered", brand:,
          occurred_at: Time.current, idempotency_key: "direct-private", properties: { email: "secret" }
        )
      end
      assert_raises(Emit::InvalidEvent) do
        Emit.call(
          event_type: "member.registered", brand:, properties: { email: "secret@example.test" },
          idempotency_key: "private-property"
        )
      end
    end

    test "rejects cross-brand profiles" do
      first_brand = Brand.create!(slug: "events-first", name: "First")
      second_brand = Brand.create!(slug: "events-second", name: "Second")
      user = User.create!
      membership = BrandMembership.create!(brand: first_brand, user:)
      profile = Profile.create!(
        brand: first_brand, user:, brand_membership: membership, display_name: "Member",
        birthdate: 30.years.ago.to_date, gender: "person"
      )

      assert_raises(Emit::InvalidEvent) do
        Emit.call(
          event_type: "profile.published", brand: second_brand, user:, profile:,
          idempotency_key: "cross-brand"
        )
      end
    end
  end
end
