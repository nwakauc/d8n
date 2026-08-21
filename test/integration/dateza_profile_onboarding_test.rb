require "test_helper"

class DatezaProfileOnboardingTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
  end

  test "server advances DateZA onboarding through required domains" do
    assert_status "profile_required", "profile"
    profile = create_required_profile
    assert_status "profile_incomplete", "preferences"

    create_required_preferences(profile)
    assert_status "profile_incomplete", "photos"

    attach_photo(profile)
    assert_status "profile_incomplete", "options"

    select_required_options(profile)
    assert_status "ready_to_publish", "publication"
    assert Profiles::Completion.call(profile:).complete?
  end

  test "optional fields do not block publication and required fields do" do
    profile = complete_profile

    assert_nil profile.occupation
    assert_empty profile.languages
    Profiles::Publication.activate!(user: @user, brand: @brand)
    assert profile.reload.active?

    Profiles::CurrentProfile.upsert!(user: @user, brand: @brand, attributes: { bio: "" })

    assert profile.reload.draft?
    assert profile.hidden?
    assert_includes Profiles::Completion.call(profile:).missing, :bio
  end

  test "public DateZA profile omits owner-only compatibility inputs and exact coordinates" do
    profile = complete_profile
    ProfileLocation.create!(
      profile:, user: @user, brand: @brand, latitude: -26.2041, longitude: 28.0473,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )

    payload = Profiles::PublicSerializer.call(profile:)

    assert_equal({ city: "Johannesburg", country_code: "ZA", precision: "approximate" }, payload.fetch(:location))
    assert_not payload.key?(:birthdate)
    assert_not payload.key?(:latitude)
    assert_not payload.key?(:longitude)
    assert_not payload.fetch(:options).key?("has_children")
    assert_not payload.fetch(:options).key?("religion_importance")
  end

  private

  def assert_status(state, next_step)
    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)
    assert_equal state, status.fetch(:state)
    assert_equal next_step, status.fetch(:next_step)
  end

  def complete_profile
    profile = create_required_profile
    create_required_preferences(profile)
    attach_photo(profile)
    select_required_options(profile)
    profile
  end

  def create_required_profile
    Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Synthetic Member", birthdate: 30.years.ago.to_date,
      gender: "person", country_code: "ZA", city: "Johannesburg",
      bio: "A synthetic DateZA test profile.", smoking: "never", drinking: "occasionally"
    )
  end

  def create_required_preferences(profile)
    ProfilePreference.create!(
      brand: @brand, user: @user, profile:, interested_in: [ "person" ],
      min_age: 25, max_age: 40, max_distance_km: 50
    )
  end

  def attach_photo(profile)
    photo = ProfilePhoto.new(profile:, user: @user, brand: @brand)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png", content_type: "image/png"
    )
    photo.save!
  end

  def select_required_options(profile)
    Profiles::OptionSelections.replace!(
      profile:,
      selections: {
        relationship_intent: [ "long_term_relationship" ],
        has_children: [ "no" ],
        wants_children: [ "maybe" ],
        religion_importance: [ "somewhat_important" ],
        social_style: [ "ambivert" ],
        meeting_pace: [ "few_days" ]
      }
    )
  end
end
