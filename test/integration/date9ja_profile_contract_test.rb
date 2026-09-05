require "test_helper"

# Slice 6 — the consumer proving ground. Date9ja travels the SAME shared stack
# as every other brand:
#
#   FieldCatalog → Date9ja brand contract → FieldPolicy → Configuration / write
#                → Profile model → serializer
#
# with no Date9ja profile subsystem and no brand-slug branching. This exercises
# the real HTTP path for writes.
class Date9jaProfileContractTest < ActionDispatch::IntegrationTest
  # The scalar capabilities the Date9ja catalogue explicitly selects today.
  ENABLED_PROFILE = %w[
    display_name birthdate gender country_code city bio smoking drinking
    occupation job_title school_or_institution looking_for_text height_cm body_type
    languages fitness
  ].freeze
  ENABLED_IDENTITY = %w[first_name last_name].freeze
  ENABLED_PREFERENCE = %w[interested_in min_age max_age max_distance_km].freeze
  # Standard canonical fields Date9ja deliberately does NOT enable.
  DISABLED_STANDARD = %w[pronouns company_name children_count languages_spoken country relationship_intent].freeze
  SENSITIVE = %w[tribe ethnicity].freeze

  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "date9ja.test"
  end

  def bearer = { "Authorization" => "Bearer #{@token}" }

  # 1 — the contract selects explicit canonical fields (no broad default).
  test "Date9ja brand contract enables an explicit canonical scalar set" do
    contract = D8n::Platform::BrandRegistry.fetch(brand: @brand)
    assert_equal ENABLED_IDENTITY, contract.enabled_identity_fields
    assert_equal ENABLED_PROFILE, contract.enabled_profile_fields
    assert_equal ENABLED_PREFERENCE, contract.enabled_preference_fields
    # It is NOT the catalogue-wide enable-able default.
    refute_equal Profiles::FieldCatalog.enableable_keys_for_group(:profile), contract.enabled_profile_fields
    DISABLED_STANDARD.each { |f| refute_includes contract.enabled_profile_fields + contract.enabled_preference_fields, f }
    SENSITIVE.each { |f| refute_includes contract.enabled_profile_fields, f }
  end

  # 2/3/4 — enabled field PATCH succeeds, persists, and comes back.
  test "PATCH /api/v1/profile writes Date9ja-enabled canonical fields end to end" do
    patch "/api/v1/profile", headers: bearer, params: {
      display_name: "Ada N", bio: "Real profile.", country_code: "ng", city: "Lagos",
      occupation: "Engineer", smoking: "never", drinking: "occasionally"
    }
    assert_response :success

    profile = Profile.find_by!(user: @user, brand: @brand)
    assert_equal "Ada N", profile.display_name
    assert_equal "Real profile.", profile.bio
    assert_equal "NG", profile.country_code
    assert_equal "Lagos", profile.city
    assert_equal "Engineer", profile.occupation
    assert_equal "never", profile.smoking

    body = JSON.parse(response.body).fetch("profile")
    assert_equal "Ada N", body.fetch("display_name")
    assert_equal "Engineer", body.fetch("occupation")
    assert_equal "never", body.fetch("smoking")
  end

  # 5 — a D8N-known but Date9ja-disabled NORMAL field is rejected.
  test "PATCH rejects a canonical field Date9ja does not enable" do
    patch "/api/v1/profile", headers: bearer, params: { display_name: "Ada", pronouns: "she/her" }
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_profile_fields", body.fetch("error")
    assert_equal [ "pronouns" ], body.fetch("details").fetch("fields")
    refute Profile.exists?(user: @user, brand: @brand)
  end

  # 6/7 — sensitive/pending capabilities are rejected on the same path.
  test "PATCH rejects tribe and ethnicity" do
    SENSITIVE.each do |field|
      patch "/api/v1/profile", headers: bearer, params: { display_name: "Ada", field => "x" }
      assert_response :unprocessable_entity, field
      body = JSON.parse(response.body)
      assert_equal "invalid_profile_fields", body.fetch("error"), field
      assert_includes body.fetch("details").fetch("fields"), field
    end
  end

  # 8/9/10 — configuration advertises only enabled Date9ja capabilities.
  test "GET /api/v1/profile/configuration advertises exactly the Date9ja scalar contract" do
    get "/api/v1/profile/configuration", headers: bearer
    assert_response :success
    config = JSON.parse(response.body).fetch("configuration")

    # Advertised in canonical catalogue order; compare as sets.
    assert_equal ENABLED_PROFILE.sort, config.fetch("profile_fields").map { |f| f.fetch("key") }.sort
    assert_equal ENABLED_IDENTITY.sort, config.fetch("identity_fields").map { |f| f.fetch("key") }.sort
    assert_equal ENABLED_PREFERENCE.sort, config.fetch("preference_fields").map { |f| f.fetch("key") }.sort
    (DISABLED_STANDARD + SENSITIVE).each do |field|
      refute_includes config.fetch("profile_fields").map { |f| f.fetch("key") }, field
      refute_includes config.fetch("preference_fields").map { |f| f.fetch("key") }, field
    end
  end

  # 11/12/13 — serialization respects the same contract, no Date9ja branch.
  test "owner / public / detail serialization respect the Date9ja contract" do
    @user.update!(first_name: "Ada", last_name: "Nwosu")
    profile = Profiles::CurrentProfile.upsert!(user: @user, brand: @brand, attributes: {
      display_name: "Ada", bio: "Hi", birthdate: 27.years.ago.to_date, gender: "woman",
      country_code: "NG", city: "Abuja", occupation: "Doctor", smoking: "never", drinking: "never"
    })
    viewer_user = User.create!
    viewer = Profile.create!(
      brand: @brand, user: viewer_user,
      brand_membership: BrandMembership.create!(brand: @brand, user: viewer_user),
      display_name: "Ben", birthdate: 30.years.ago.to_date, gender: "man",
      status: :active, visibility: :visible
    )

    owner = Profiles::OwnerSerializer.call(profile:)
    assert_equal "Ada", owner[:display_name]
    assert_equal "Abuja", owner[:city]
    assert_equal profile.birthdate.iso8601, owner[:birthdate]      # owner-only, enabled
    assert_equal "Ada", owner[:first_name]                          # identity, enabled
    (DISABLED_STANDARD + SENSITIVE).each { |f| refute owner.key?(f.to_sym), f }

    public_payload = Profiles::PublicSerializer.call(profile:)
    assert_equal "Ada", public_payload[:display_name]
    assert_equal "Doctor", public_payload[:occupation]
    refute public_payload.key?(:birthdate)                         # owner-only ceiling
    refute public_payload.key?(:first_name)
    (DISABLED_STANDARD + SENSITIVE).each { |f| refute public_payload.key?(f.to_sym), f }

    detail = Profiles::DetailSerializer.call(profile:, viewer:)
    assert_equal "Ada", detail[:display_name]
    refute detail.key?(:birthdate)
    SENSITIVE.each { |f| refute detail.key?(f.to_sym), f }
  end

  # 14 — the preference scalar path uses the same stack.
  test "PATCH /api/v1/profile/preferences writes enabled preference scalars and rejects disabled ones" do
    Profiles::CurrentProfile.upsert!(user: @user, brand: @brand, attributes: {
      display_name: "Ada", birthdate: 27.years.ago.to_date, gender: "woman"
    })

    patch "/api/v1/profile/preferences", headers: bearer,
      params: { interested_in: [ "man" ], min_age: 25, max_age: 40, max_distance_km: 60 }
    assert_response :success
    preference = ProfilePreference.find_by!(user: @user, brand: @brand)
    assert_equal [ "man" ], preference.interested_in
    assert_equal 25, preference.min_age
    assert_equal 60, preference.max_distance_km

    patch "/api/v1/profile/preferences", headers: bearer, params: { country: "NG" }
    assert_response :unprocessable_entity
    assert_equal "invalid_preference_fields", JSON.parse(response.body).fetch("error")
  end

  # 15 — no brand-slug branching was introduced in the shared profile stack.
  test "no Date9ja brand-slug branching in the shared profile code" do
    %w[
      app/controllers/api/v1/profile_controller.rb
      app/controllers/api/v1/profile_preferences_controller.rb
      domains/profiles/field_policy.rb
      domains/profiles/field_catalog.rb
      domains/profiles/configuration.rb
      domains/profiles/owner_serializer.rb
      domains/profiles/public_serializer.rb
      domains/profiles/detail_serializer.rb
      app/models/profile.rb
      app/models/profile_preference.rb
    ].each do |file|
      source = File.read(Rails.root.join(file))
      refute_match(/slug\s*==|when\s+"(date9ja|hookus|dateza)"|case\s+[^\n]*slug/, source, file)
    end
  end

  # 16/17 — making Date9ja explicit changed nothing for the other brands.
  test "DateZA and HookUs contracts are unaffected" do
    dateza = Brand.new(slug: "dateza", name: "DateZA",
      profile_requirements: Profiles::DatezaProfileCatalog::REQUIREMENTS)
    hookus = Brand.new(slug: "hookus", name: "HookUs",
      profile_requirements: Profiles::HookusProfileCatalog::REQUIREMENTS)

    assert_equal(
      (Profiles::DatezaProfileCatalog::REQUIRED_PROFILE_FIELDS +
        Profiles::DatezaProfileCatalog::OPTIONAL_PROFILE_FIELDS),
      Profiles::FieldPolicy.new(brand: dateza).enabled_profile_fields
    )
    # HookUs has no explicit list -> the enable-able default (never sensitive).
    assert_equal Profiles::FieldCatalog.enableable_keys_for_group(:profile),
      Profiles::FieldPolicy.new(brand: hookus).enabled_profile_fields
  end
end
