require "test_helper"

class LegacyReferenceTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
    )
  end

  def valid_attrs(**overrides)
    {
      source_system: "date9ja", source_entity: "profile", source_id: "4021",
      destination_type: "Profile", destination_id: @profile.id, brand: @brand,
      importer_version: "v1"
    }.merge(overrides)
  end

  test "persists a brand-owned binding and reloads" do
    reference = LegacyReference.create!(valid_attrs)

    reference.reload
    assert_equal "date9ja", reference.source_system
    assert_equal @profile, reference.destination
    assert reference.resolvable?
    assert_equal @brand, reference.brand
  end

  test "rejects an unknown source system" do
    reference = LegacyReference.new(valid_attrs(source_system: "myspace"))

    assert_not reference.valid?
    assert_includes reference.errors[:source_system], "is not a known migration source system"
  end

  test "rejects a malformed source entity" do
    assert_not LegacyReference.new(valid_attrs(source_entity: "Profile Row")).valid?
  end

  test "rejects an unbindable destination type" do
    reference = LegacyReference.new(valid_attrs(destination_type: "AdminUser"))

    assert_not reference.valid?
    assert_includes reference.errors[:destination_type], "is not a bindable D8N destination type"
  end

  test "requires a brand for a brand-owned destination" do
    reference = LegacyReference.new(valid_attrs(brand: nil))

    assert_not reference.valid?
    assert_includes reference.errors[:brand], "is required for a brand-owned destination"
  end

  test "forbids a brand on a platform-owned destination" do
    reference = LegacyReference.new(
      valid_attrs(destination_type: "User", destination_id: @user.id, brand: @brand)
    )

    assert_not reference.valid?
    assert_includes reference.errors[:brand], "must be null for a platform-owned destination"
  end

  test "database enforces one destination per source key" do
    LegacyReference.create!(valid_attrs)
    # Same source key, different destination id — model rejects, and so does the
    # DB (idx_legacy_references_source_key) when validations are skipped.
    dup = LegacyReference.new(valid_attrs(destination_id: another_profile.id))

    assert_not dup.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "database enforces one source per destination" do
    LegacyReference.create!(valid_attrs)
    # Different source key, same destination — model rejects, and so does the DB
    # (idx_legacy_references_destination_key) when validations are skipped.
    other = LegacyReference.new(valid_attrs(source_id: "9999"))

    assert_not other.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { other.save!(validate: false) }
  end

  test "the binding columns are immutable after creation" do
    reference = LegacyReference.create!(valid_attrs)

    reference.destination_id = another_profile.id
    error = assert_raises(ActiveRecord::ReadOnlyRecord) { reference.save! }
    assert_match(/immutable/, error.message)
  end

  test "metadata columns stay updatable" do
    reference = LegacyReference.create!(valid_attrs(source_fingerprint: "abc"))

    assert_nothing_raised do
      reference.update!(source_fingerprint: "def", importer_version: "v2")
    end
    assert_equal "def", reference.reload.source_fingerprint
  end

  test "redacted key never contains the raw source id" do
    reference = LegacyReference.create!(valid_attrs(source_id: "secret-legacy-4021"))

    assert_not_includes reference.redacted_key, "secret-legacy-4021"
    assert_match(/\Adate9ja:profile:[0-9a-f]{12}\z/, reference.redacted_key)
  end

  private

  def another_profile
    @another_profile ||= begin
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      Profile.create!(
        brand: @brand, user:, brand_membership: membership,
        display_name: "Bola", birthdate: 29.years.ago.to_date, gender: "man"
      )
    end
  end
end
