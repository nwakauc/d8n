require "test_helper"

class Profiles::StatusFieldsTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @viewer = build_profile
  end

  test "returns empty for no profiles" do
    assert_empty status_fields(viewer: @viewer, profiles: [])
  end

  test "returns empty when there is no viewer" do
    assert_empty status_fields(viewer: nil, profiles: [ build_profile ])
  end

  test "flags verified only when the member has a verified identifier" do
    verified = build_profile
    IdentityIdentifier.create!(user: verified.user, kind: :email, normalized_value: "v@example.com", verified_at: Time.current)
    unverified = build_profile
    IdentityIdentifier.create!(user: unverified.user, kind: :email, normalized_value: "u@example.com", verified_at: nil)

    status = status_fields(viewer: @viewer, profiles: [ verified, unverified ])

    assert status.fetch(verified.id).fetch(:verified)
    assert_not status.fetch(unverified.id).fetch(:verified)
  end

  test "marks online within the window and reports last_active_at" do
    online = build_profile
    session = Session.issue!(brand: @brand, user: online.user).last
    session.update!(last_used_at: 2.minutes.ago)
    idle = build_profile
    Session.issue!(brand: @brand, user: idle.user).last.update!(last_used_at: 1.hour.ago)

    status = status_fields(viewer: @viewer, profiles: [ online, idle ])

    assert status.fetch(online.id).fetch(:online)
    assert_equal session.reload.last_used_at.iso8601, status.fetch(online.id).fetch(:last_active_at)
    assert_not status.fetch(idle.id).fetch(:online)
    assert status.fetch(idle.id).fetch(:last_active_at).present?
  end

  test "ignores presence from other brands, revoked, and expired sessions" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    member = build_profile
    Session.issue!(brand: other_brand, user: member.user).last.update!(last_used_at: 1.minute.ago)
    Session.issue!(brand: @brand, user: member.user).last.update!(last_used_at: 1.minute.ago, revoked_at: Time.current)
    Session.issue!(brand: @brand, user: member.user).last.update!(last_used_at: 1.minute.ago, expires_at: 1.hour.ago)

    status = status_fields(viewer: @viewer, profiles: [ member ])

    assert_not status.fetch(member.id).fetch(:online)
    assert_nil status.fetch(member.id).fetch(:last_active_at)
  end

  test "computes rounded viewer-relative distance only when both have fresh locations" do
    near = build_profile
    far = build_profile
    no_location = build_profile
    put_location(@viewer, lat: 6.5244, lon: 3.3792) # Lagos
    put_location(near, lat: 6.4531, lon: 3.3958)     # ~8km away
    put_location(far, lat: 9.0579, lon: 7.4951)      # Abuja, hundreds of km

    status = status_fields(viewer: @viewer, profiles: [ near, far, no_location ])

    assert_operator status.fetch(near.id).fetch(:distance_km), :>=, 1
    assert_operator status.fetch(near.id).fetch(:distance_km), :<, 15
    assert_operator status.fetch(far.id).fetch(:distance_km), :>, 400
    assert_nil status.fetch(no_location.id).fetch(:distance_km)
  end

  test "distance is nil for everyone when the viewer has no fresh location" do
    member = build_profile
    put_location(member, lat: 6.45, lon: 3.39)

    status = status_fields(viewer: @viewer, profiles: [ member ])

    assert_nil status.fetch(member.id).fetch(:distance_km)
  end

  test "treats a stale candidate location as absent" do
    member = build_profile
    put_location(@viewer, lat: 6.52, lon: 3.37)
    put_location(member, lat: 6.45, lon: 3.39, captured_at: 2.days.ago)

    status = status_fields(viewer: @viewer, profiles: [ member ])

    assert_nil status.fetch(member.id).fetch(:distance_km)
  end

  test "floors sub-kilometre distance to 1 km rather than reading as co-location" do
    member = build_profile
    put_location(@viewer, lat: 6.5244, lon: 3.3792)
    put_location(member, lat: 6.5246, lon: 3.3794) # a few metres away

    status = status_fields(viewer: @viewer, profiles: [ member ])

    assert_equal 1, status.fetch(member.id).fetch(:distance_km)
  end

  private

  def status_fields(viewer:, profiles:)
    Profiles::StatusFields.call(
      viewer:, profiles:, eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
    )
  end

  def build_profile
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    Profile.create!(
      brand: @brand, user:, brand_membership: membership, gender: "man",
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
  end

  def put_location(profile, lat:, lon:, captured_at: Time.current)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand,
      latitude: lat, longitude: lon, accuracy_meters: 20, source: "device", captured_at:
    )
  end
end
