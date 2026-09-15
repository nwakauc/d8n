require "test_helper"

class Trust::AwardEventTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "creates a TrustEvent" do
    event = Trust::AwardEvent.call(
      user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1"
    )

    assert event.persisted?
    assert_equal 25, event.points
  end

  test "is idempotent: a repeated call with the same key never double-awards" do
    Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")
    Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")

    assert_equal 1, TrustEvent.where(brand: @brand, user: @user).count
  end

  test "concurrent-safe: a race that hits the unique index returns the existing row instead of raising" do
    TrustEvent.create!(
      brand: @brand, user: @user, event_type: "realme_email_approved", points: 25,
      idempotency_key: "k1", occurred_at: Time.current
    )

    event = Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")

    assert_equal 1, TrustEvent.where(brand: @brand, user: @user).count
    assert_equal 25, event.points
  end

  # Migration preserves trust; migration itself does not earn trust. Real
  # historical trust for a migrated member is preserved separately, verbatim,
  # by Date9ja::Import::TrustLedgerImport -- this only suppresses a FRESH
  # award minted as a side effect of an import task driving shared runtime
  # code (e.g. Profiles::Publication) to reconstruct historical state.
  test "inside Migration::ImportContext.as_migration, no TrustEvent is created" do
    event = Migration::ImportContext.as_migration do
      Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "profile_completed", points: 110, idempotency_key: "activity:1:profile_completed")
    end

    assert_nil event
    assert_equal 0, TrustEvent.where(brand: @brand, user: @user).count
  end

  test "the suppression does not leak outside the block: an award immediately after the block still works" do
    Migration::ImportContext.as_migration { Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "profile_completed", points: 110, idempotency_key: "activity:1:profile_completed") }

    event = Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "profile_completed", points: 110, idempotency_key: "activity:1:profile_completed")

    assert event.persisted?
    assert_equal 1, TrustEvent.where(brand: @brand, user: @user).count
  end

  test "a nested as_migration block does not prematurely lift suppression when the inner block exits" do
    Migration::ImportContext.as_migration do
      Migration::ImportContext.as_migration do
        # no-op inner block
      end
      event = Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "profile_completed", points: 110, idempotency_key: "activity:1:profile_completed")
      assert_nil event
    end
  end
end
