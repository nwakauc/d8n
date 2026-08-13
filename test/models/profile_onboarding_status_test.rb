require "test_helper"

class ProfileOnboardingStatusTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
  end

  test "directs a new member to create the current brand profile" do
    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)

    assert_equal "profile_required", status.fetch(:state)
    assert_equal "profile", status.fetch(:next_step)
    assert_equal false, status.fetch(:profile_exists)
    assert_equal false, status.fetch(:profile_complete)
    assert_equal false, status.fetch(:profile_published)
    assert_equal 0, status.dig(:completion, :percent)
    assert_includes status.dig(:completion, :missing), "display_name"
    assert_includes status.dig(:completion, :missing), "preferences.min_age"
    assert_includes status.dig(:completion, :missing), "photos"
  end

  test "selects the next incomplete domain from the brand completion contract" do
    create_required_profile

    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)

    assert_equal "profile_incomplete", status.fetch(:state)
    assert_equal "preferences", status.fetch(:next_step)
    assert_equal true, status.fetch(:profile_exists)
  end

  test "directs a complete draft profile to publication" do
    profile = create_complete_profile

    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)

    assert profile.draft?
    assert_equal "ready_to_publish", status.fetch(:state)
    assert_equal "publication", status.fetch(:next_step)
    assert_equal true, status.fetch(:profile_complete)
    assert_equal false, status.fetch(:profile_published)
  end

  test "reports a published profile as complete" do
    profile = create_complete_profile
    profile.update!(status: :active, visibility: :visible)

    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)

    assert_equal "complete", status.fetch(:state)
    assert_nil status.fetch(:next_step)
    assert_equal true, status.fetch(:profile_published)
  end

  test "does not direct a suspended profile through onboarding" do
    profile = create_required_profile
    profile.update!(status: :suspended)

    status = Profiles::OnboardingStatus.call(user: @user, brand: @brand)

    assert_equal "profile_suspended", status.fetch(:state)
    assert_nil status.fetch(:next_step)
  end

  private

  def create_required_profile
    Profile.create!(
      user: @user,
      brand: @brand,
      brand_membership: @membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )
  end

  def create_complete_profile
    profile = create_required_profile
    ProfilePreference.create!(
      profile:,
      user: @user,
      brand: @brand,
      min_age: 25,
      max_age: 35,
      interested_in: [ "man" ]
    )
    photo = ProfilePhoto.new(profile:, user: @user, brand: @brand)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png",
      content_type: "image/png"
    )
    photo.save!
    profile
  end
end
