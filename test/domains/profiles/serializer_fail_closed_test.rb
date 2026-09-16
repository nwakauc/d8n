require "test_helper"

module Profiles
  # Slice 3 — defense in depth. A sensitive-identity field and a pending-storage
  # field must never reach ANY serializer output, even when a malformed / test
  # brand configuration names them in enabled_profile_fields. Primary evidence is
  # behavioural (payload inspection); a brand-slug grep is only supporting.
  class SerializerFailClosedTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "failclosed", name: "FailClosed", profile_requirements: {
        "profile_fields" => %w[display_name],
        "enabled_profile_fields" => %w[display_name bio],
        "enabled_identity_fields" => %w[first_name],
        "identity_fields" => %w[first_name]
      })
      @user = User.create!(first_name: "Ada")
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", bio: "hi", birthdate: 25.years.ago.to_date, gender: "woman",
        status: :active, visibility: :visible
      )
      @viewer_user = User.create!
      @viewer_membership = BrandMembership.create!(brand: @brand, user: @viewer_user)
      @viewer = Profile.create!(
        brand: @brand, user: @viewer_user, brand_membership: @viewer_membership,
        display_name: "Ben", birthdate: 30.years.ago.to_date, gender: "man",
        status: :active, visibility: :visible
      )
    end

    # A hostile in-memory config that names a sensitive field and a not-yet-stored
    # one. Not saved — Brand validation would (correctly) reject it; the point is
    # that even if it slipped through, nothing leaks.
    def enable_hostile_fields!
      @brand.profile_requirements = @brand.profile_requirements.merge(
        "enabled_profile_fields" => %w[display_name bio tribe genotype]
      )
    end

    def sensitive_field(audience: :owner_only)
      FieldCatalog::Field.new(
        key: "tribe", group: :profile, label: "Tribe", data_type: :string,
        storage: { record: :profile, column: :bio }, # a real column, so a value could exist
        sensitivity: :sensitive_identity, default_audience: audience,
        validation: { max_length: 60 }
      )
    end

    def pending_field
      FieldCatalog::Field.new(
        key: "genotype", group: :profile, label: "Genotype", data_type: :string,
        storage: { record: :pending }, sensitivity: :sensitive_identity,
        default_audience: :owner_only, validation: { max_length: 8 }
      )
    end

    test "sensitive_identity + pending fields never leak through OwnerSerializer" do
      with_field_catalog_extra(sensitive_field, pending_field) do
        enable_hostile_fields!
        payload = OwnerSerializer.call(profile: @profile)

        refute payload.key?(:tribe)
        refute payload.key?(:genotype)
        assert_equal "Ada", payload[:display_name]
        assert_equal "hi", payload[:bio]
        assert_equal "Ada", payload[:first_name]
      end
    end

    test "sensitive_identity + pending fields never leak through PublicSerializer" do
      with_field_catalog_extra(sensitive_field, pending_field) do
        enable_hostile_fields!
        payload = PublicSerializer.call(profile: @profile)

        refute payload.key?(:tribe)
        refute payload.key?(:genotype)
        assert_equal "Ada", payload[:display_name]
        assert_equal "hi", payload[:bio]
      end
    end

    test "sensitive_identity + pending fields never leak through DetailSerializer" do
      with_field_catalog_extra(sensitive_field, pending_field) do
        enable_hostile_fields!
        payload = DetailSerializer.call(profile: @profile, viewer: @viewer)

        refute payload.key?(:tribe)
        refute payload.key?(:genotype)
        assert_equal "Ada", payload[:display_name]
      end
    end

    test "a sensitive field with a widened public audience is still withheld everywhere" do
      with_field_catalog_extra(sensitive_field(audience: :public)) do
        enable_hostile_fields!
        refute PublicSerializer.call(profile: @profile).key?(:tribe)
        refute OwnerSerializer.call(profile: @profile).key?(:tribe)
        refute DetailSerializer.call(profile: @profile, viewer: @viewer).key?(:tribe)
      end
    end

    test "profile serializers carry no brand-slug branching (supporting evidence)" do
      %w[owner_serializer public_serializer detail_serializer].each do |file|
        source = File.read(Rails.root.join("domains/profiles/#{file}.rb"))
        refute_match(/slug\s*==|slug\s*\.\s*in\?|when\s+"(date9ja|hookus|dateza)"|case\s+[^\n]*slug/, source, file)
      end
    end
  end
end
