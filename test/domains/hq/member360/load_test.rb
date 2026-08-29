require "test_helper"

class Hq::Member360::LoadTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @other = Brand.create!(slug: "other", name: "Other")
    @user = User.create!(first_name: "Ada", last_name: "Okafor")
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership, display_name: "Ada",
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand: @brand, user: @user, profile: @profile, min_age: 21, max_age: 40, interested_in: [ "person" ]
    )
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "ada@example.com")
  end

  test "returns all six sections for a member with a profile" do
    sections = Hq::Member360::Load.call(brand: @brand, brand_membership: @membership)

    assert_equal %i[identity profile product comms safety activity], sections.keys

    assert_equal @user.id, sections[:identity][:user_id]
    assert_equal "Ada", sections[:identity][:first_name]
    assert_equal 1, sections[:identity][:identifiers].size
    assert_equal "ada@example.com", sections[:identity][:identifiers].first[:value]

    assert sections[:profile][:exists]
    assert_equal @profile.public_id, sections[:profile][:public_id]
    assert_equal 21, sections[:profile][:preference][:min_age]

    assert_equal 0, sections[:product][:likes_given]
    assert_equal 0, sections[:safety][:reports_filed_count]
    assert_nil sections[:safety][:active_enforcement]
    assert_nil sections[:activity][:last_login_at]
  end

  test "handles a member with no profile yet without crashing" do
    bare_user = User.create!
    bare_membership = BrandMembership.create!(brand: @brand, user: bare_user)

    sections = Hq::Member360::Load.call(brand: @brand, brand_membership: bare_membership)

    assert_equal false, sections[:profile][:exists]
    assert_equal 0, sections[:product][:likes_given]
    assert_equal [], sections[:product][:recent_conversations]
    assert_equal 0, sections[:safety][:reports_filed_count]
  end

  test "product section counts likes, matches, and hooks accurately" do
    other_profile = create_profile(brand: @brand, display_name: "Sam")
    Like.create!(brand: @brand, liker_profile: @profile, liked_profile: other_profile)
    Like.create!(brand: @brand, liker_profile: other_profile, liked_profile: @profile)
    profile_a_id, profile_b_id = Match.canonical_pair(@profile.id, other_profile.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)

    sections = Hq::Member360::Load.call(brand: @brand, brand_membership: @membership)

    assert_equal 1, sections[:product][:likes_given]
    assert_equal 1, sections[:product][:likes_received]
    assert_equal 1, sections[:product][:matches_active]
  end

  test "safety section summarizes reports filed and received, and active enforcement" do
    other_profile = create_profile(brand: @brand, display_name: "Sam")
    Report.create!(brand: @brand, reporter_profile: @profile, reported_profile: other_profile, reason: :spam)
    Report.create!(brand: @brand, reporter_profile: other_profile, reported_profile: @profile, reason: :harassment)
    admin_user = AdminUser.create!(status: :active)
    AccountEnforcement.create!(
      brand: @brand, user: @user, brand_membership: @membership, profile: @profile, admin_user:, reason: "test"
    )

    sections = Hq::Member360::Load.call(brand: @brand, brand_membership: @membership)

    assert_equal 1, sections[:safety][:reports_filed_count]
    assert_equal 1, sections[:safety][:reports_received_count]
    assert_equal 2, sections[:safety][:recent_reports].size
    assert_equal "active", sections[:safety][:active_enforcement][:state]
    assert_equal 1, sections[:safety][:enforcement_count]
  end

  test "activity section reflects auth attempts and security events for this user only, brand-scoped" do
    AuthAttempt.create!(
      brand: @brand, user: @user, kind: :password, result: :succeeded, identifier: "ada@example.com"
    )
    AuthAttempt.create!(
      brand: @other, user: @user, kind: :password, result: :succeeded, identifier: "ada@example.com"
    )
    SecurityEvent.create!(brand: @brand, user: @user, event_type: "identity.password_changed", severity: :info)

    sections = Hq::Member360::Load.call(brand: @brand, brand_membership: @membership)

    assert_equal 1, sections[:activity][:recent_auth_attempts].size
    assert sections[:activity][:last_login_at].present?
    assert_equal 1, sections[:activity][:recent_security_events].size
  end

  private

  def create_profile(brand:, display_name:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 28.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
  end
end
