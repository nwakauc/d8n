require "test_helper"

class MigrationProfileReadinessTest < ActiveSupport::TestCase
  test "allows a PII-free technical failure without a destination" do
    brand = Brand.create!(slug: "date9ja", name: "Date9ja")

    readiness = Migration::ProfileReadiness.create!(
      brand:, source_system: "date9ja", source_entity: "user", source_id: "1",
      disposition: :failed, reason_codes: %w[technical_failure technical_failure],
      importer_version: "test-v1", assessed_at: Time.current
    )

    assert_equal [ "technical_failure" ], readiness.reason_codes
    assert_nil readiness.profile
    assert_nil readiness.user
  end

  test "requires a scoped destination for a resolved disposition" do
    brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    readiness = Migration::ProfileReadiness.new(
      brand:, source_system: "date9ja", source_entity: "user", source_id: "1",
      disposition: :ready, reason_codes: [], importer_version: "test-v1", assessed_at: Time.current
    )

    assert_not readiness.valid?
    assert_includes readiness.errors[:profile], "is required for a resolved disposition"
  end

  test "rejects unsafe reason text" do
    brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    readiness = Migration::ProfileReadiness.new(
      brand:, source_system: "date9ja", source_entity: "user", source_id: "1",
      disposition: :failed, reason_codes: [ "email=member@example.test" ],
      importer_version: "test-v1", assessed_at: Time.current
    )

    assert_not readiness.valid?
    assert_includes readiness.errors[:reason_codes], "contains an invalid code"
  end

  test "database rejects a cross-tenant profile owner tuple" do
    brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_brand = Brand.create!(slug: "dateza", name: "DateZA")
    user = User.create!
    other_user = User.create!
    profile = Profile.create!(
      brand:, user:, brand_membership: BrandMembership.create!(brand:, user:)
    )

    assert_raises(ActiveRecord::InvalidForeignKey) do
      Migration::ProfileReadiness.insert_all!([ {
        brand_id: other_brand.id,
        user_id: other_user.id,
        profile_id: profile.id,
        source_system: "date9ja",
        source_entity: "user",
        source_id: "1",
        disposition: Migration::ProfileReadiness.dispositions.fetch("ready"),
        reason_codes: [],
        importer_version: "test-v1",
        assessed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end
end
