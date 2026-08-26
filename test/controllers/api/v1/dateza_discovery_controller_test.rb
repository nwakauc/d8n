require "test_helper"

class Api::V1::DatezaDiscoveryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @viewer = create_profile(
      brand: @brand, gender: "woman", age: 30,
      interested_in: [ "man" ], min_age: 18, max_age: 60
    )
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "dateza.test"
  end

  test "creates one finalized batch of at most ten and keeps candidates and order stable" do
    candidates = 11.times.map do |index|
      create_candidate(created_at: Time.utc(2026, 8, 24, 10, 0, index))
    end

    travel_to Time.utc(2026, 8, 24, 12, 0, 0) do
      get "/api/v1/discovery", headers: bearer_headers
      first = JSON.parse(response.body)

      assert_response :success
      assert_equal candidates.last(10).reverse.map(&:public_id), first.fetch("profiles").pluck("id")
      assert_nil first.fetch("next_cursor")
      assert_equal({
        "allocation_date" => "2026-08-24",
        "daily_limit" => 10,
        "count" => 10,
        "finalized" => true,
        "refreshes_at" => "2026-08-25T00:00:00+02:00"
      }, first.fetch("selection"))

      late_candidate = create_candidate(created_at: Time.utc(2026, 8, 24, 12, 30, 0))
      get "/api/v1/discovery", headers: bearer_headers
      repeated = JSON.parse(response.body)

      assert_equal first.fetch("profiles").pluck("id"), repeated.fetch("profiles").pluck("id")
      assert_not_includes repeated.fetch("profiles").pluck("id"), late_candidate.public_id
    end

    allocation = DiscoveryAllocation.where(brand: @brand, brand_membership: @viewer.brand_membership).sole
    assert_equal "discovery.curated_daily", allocation.surface_key
    assert_equal "dateza_v1", allocation.strategy_key
    assert_equal 10, allocation.allocation_candidates.count
    assert_equal (1..10).to_a, allocation.allocation_candidates.pluck(:position)
  end

  test "returns honest partial and empty finalized batches" do
    candidate = create_candidate

    get "/api/v1/discovery", headers: bearer_headers
    partial = JSON.parse(response.body)

    assert_equal [ candidate.public_id ], partial.fetch("profiles").pluck("id")
    assert_equal 1, partial.dig("selection", "count")
    assert_equal 10, partial.dig("selection", "daily_limit")
    assert partial.dig("selection", "finalized")

    other_viewer = create_profile(
      brand: @brand, gender: "person", age: 30,
      interested_in: [ "person" ], min_age: 18, max_age: 60
    )
    other_token, = Session.issue!(brand: @brand, user: other_viewer.user)

    get "/api/v1/discovery", headers: bearer_headers(other_token)
    empty = JSON.parse(response.body)

    assert_response :success
    assert_empty empty.fetch("profiles")
    assert_equal 0, empty.dig("selection", "count")
    assert_equal 0, DiscoveryAllocation.where(viewer_profile: other_viewer).sole.allocation_candidates.count
  end

  test "uses shared eligibility and never allocates another brand" do
    eligible = create_candidate
    create_candidate(profile_attributes: { visibility: :hidden })
    create_candidate(profile_attributes: { status: :draft })
    create_candidate(membership_status: :suspended)
    create_candidate(user_status: :suspended)
    create_candidate(gender: "person")
    create_candidate(interested_in: [ "man" ])
    create_candidate(age: 61)
    create_candidate(min_age: 31)
    blocked = create_candidate
    ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: blocked)
    other_brand = Brand.create!(slug: "daily-other", name: "Other")
    other = create_profile(
      brand: other_brand, gender: "man", age: 30,
      interested_in: [ "woman" ], min_age: 18, max_age: 60
    )

    get "/api/v1/discovery", headers: bearer_headers

    ids = JSON.parse(response.body).fetch("profiles").pluck("id")
    assert_equal [ eligible.public_id ], ids
    assert_not_includes ids, other.public_id
    assert_equal [ eligible.id ], DiscoveryAllocationCandidate.where(brand: @brand).pluck(:candidate_profile_id)
  end

  test "applies the shared bilateral distance policy before allocation" do
    @viewer.profile_preference.update!(max_distance_km: 100)
    create_location(@viewer, latitude: -26.2041, longitude: 28.0473)
    near = create_candidate
    create_location(near, latitude: -26.205, longitude: 28.048)
    far = create_candidate
    create_location(far, latitude: -33.9249, longitude: 18.4241)
    candidate_requiring_nearby = create_candidate
    candidate_requiring_nearby.profile_preference.update!(max_distance_km: 5)
    create_location(candidate_requiring_nearby, latitude: -29.8587, longitude: 31.0218)

    get "/api/v1/discovery", headers: bearer_headers

    assert_equal [ near.public_id ], JSON.parse(response.body).fetch("profiles").pluck("id")
  end

  test "uses configured DateZA compatibility ranking and persists its payload" do
    strongest = create_candidate(created_at: 1.hour.ago)
    weaker = create_candidate(created_at: Time.current)
    compatible_values = {
      relationship_intent: [ "long_term_relationship" ],
      has_children: [ "no" ],
      wants_children: [ "yes" ],
      religion_importance: [ "somewhat_important" ],
      social_style: [ "ambivert" ],
      meeting_pace: [ "few_days" ]
    }
    [ @viewer, strongest ].each do |profile|
      profile.update!(smoking: "never", drinking: "occasionally")
      Profiles::OptionSelections.replace!(profile:, selections: compatible_values)
      profile.update!(status: :active, visibility: :visible)
    end
    weaker.update!(smoking: "regularly", drinking: "regularly")
    Profiles::OptionSelections.replace!(profile: weaker, selections: {
      relationship_intent: [ "friendship" ], wants_children: [ "no" ],
      has_children: [ "yes" ], religion_importance: [ "not_important" ],
      social_style: [ "introverted" ], meeting_pace: [ "chat_first" ]
    })
    weaker.update!(status: :active, visibility: :visible)

    get "/api/v1/discovery", headers: bearer_headers
    profiles = JSON.parse(response.body).fetch("profiles")

    assert_equal strongest.public_id, profiles.first.fetch("id")
    assert_equal "dateza_v1", profiles.first.dig("compatibility", "version")
    assert_operator profiles.first.dig("compatibility", "score"), :>, profiles.last.dig("compatibility", "score")
    stored = DiscoveryAllocationCandidate.order(:position).first.ranking_payload.fetch("compatibility")
    assert_equal profiles.first.fetch("compatibility"), stored
  end

  test "filters invalidated and interacted candidates without refilling or reordering survivors" do
    candidates = 6.times.map { |index| create_candidate(created_at: index.minutes.ago) }
    get "/api/v1/discovery", headers: bearer_headers
    allocated_ids = JSON.parse(response.body).fetch("profiles").pluck("id")

    by_public_id = candidates.index_by(&:public_id)
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: by_public_id.fetch(allocated_ids[0]))
    ProfilePass.create!(brand: @brand, passer_profile: @viewer, passed_profile: by_public_id.fetch(allocated_ids[1]))
    matched = by_public_id.fetch(allocated_ids[2])
    profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, matched.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    ProfileBlock.create!(
      brand: @brand, blocker_profile: @viewer,
      blocked_profile: by_public_id.fetch(allocated_ids[3])
    )
    by_public_id.fetch(allocated_ids[4]).update!(visibility: :hidden)
    by_public_id.fetch(allocated_ids[5]).brand_membership.update!(status: :left)
    replacement = create_candidate(created_at: 1.second.from_now)

    get "/api/v1/discovery", headers: bearer_headers
    payload = JSON.parse(response.body)

    assert_empty payload.fetch("profiles")
    assert_equal 0, payload.dig("selection", "count")
    assert_not_includes payload.fetch("profiles").pluck("id"), replacement.public_id
    assert_equal 6, DiscoveryAllocationCandidate.where(brand: @brand).count
  end

  test "rolls over at Johannesburg midnight while retaining history" do
    candidates = 12.times.map { |index| create_candidate(created_at: index.minutes.ago) }

    travel_to Time.utc(2026, 8, 24, 21, 59, 59) do
      get "/api/v1/discovery", headers: bearer_headers
      assert_equal "2026-08-24", JSON.parse(response.body).dig("selection", "allocation_date")
    end
    first_ids = DiscoveryAllocation.order(:allocation_date).first.allocation_candidates.pluck(:candidate_profile_id)

    travel_to Time.utc(2026, 8, 24, 22, 0, 0) do
      candidates.last.update!(visibility: :hidden)
      get "/api/v1/discovery", headers: bearer_headers
      assert_equal "2026-08-25", JSON.parse(response.body).dig("selection", "allocation_date")
    end

    assert_equal 2, DiscoveryAllocation.where(brand: @brand, brand_membership: @viewer.brand_membership).count
    assert_equal first_ids, DiscoveryAllocation.order(:allocation_date).first.allocation_candidates.pluck(:candidate_profile_id)
  end

  test "keeps Discover allocation and Find exposure allowances independent" do
    12.times { |index| create_candidate(created_at: index.minutes.ago) }

    get "/api/v1/discovery", headers: bearer_headers
    discover = JSON.parse(response.body)
    allocation_ids = DiscoveryAllocationCandidate.where(brand: @brand).order(:position).pluck(:candidate_profile_id)

    get "/api/v1/find", headers: bearer_headers
    find = JSON.parse(response.body)

    assert_equal 10, discover.fetch("profiles").size
    assert_equal 10, allocation_ids.size
    assert_equal 10, find.fetch("profiles").size
    assert_equal 10, find.dig("allowance", "used")
    assert_equal 10, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
    assert_equal allocation_ids, DiscoveryAllocationCandidate.where(brand: @brand).order(:position).pluck(:candidate_profile_id)

    get "/api/v1/discovery", headers: bearer_headers

    assert_equal 10, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
    assert_equal 1, DiscoveryAllocation.where(brand: @brand, brand_membership: @viewer.brand_membership).count
  end

  test "a processed pending-review DateZA photo is deliverable in Discover, still awaiting moderation" do
    candidate = create_candidate
    photo = attach_photo(candidate)
    assert photo.pending_review?
    assert photo.visible?

    get "/api/v1/discovery", headers: bearer_headers
    photos = JSON.parse(response.body).fetch("profiles").sole.fetch("photos")

    assert_equal [ photo.public_id ], photos.map { |entry| entry.fetch("id") }
  end

  test "an unprocessed or rejected DateZA photo never reaches Discover" do
    candidate = create_candidate
    attach_photo(candidate, processing_state: :pending)
    rejected = create_candidate
    attach_photo(rejected, status: :rejected)

    get "/api/v1/discovery", headers: bearer_headers
    profiles = JSON.parse(response.body).fetch("profiles")

    assert_equal [ candidate.public_id, rejected.public_id ].sort, profiles.pluck("id").sort
    profiles.each { |profile| assert_empty profile.fetch("photos") }
  end

  private

  def create_candidate(**attributes)
    create_profile(
      brand: @brand, gender: "man", age: 30,
      interested_in: [ "woman" ], min_age: 18, max_age: 60, **attributes
    )
  end

  def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:,
    profile_attributes: {}, membership_status: :active, user_status: :active, created_at: nil)
    user = User.create!(status: user_status)
    membership = BrandMembership.create!(brand:, user:, status: membership_status)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:, birthdate: age.years.ago.to_date,
      status: :active, visibility: :visible, **profile_attributes
    )
    profile.update_columns(created_at:, updated_at: created_at) if created_at
    ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:)
    profile
  end

  def bearer_headers(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  def attach_photo(profile, processing_state: :ready, status: nil)
    initial = Media::PhotoPolicy.initial_state(brand: profile.brand)
    photo = ProfilePhoto.new(
      brand: profile.brand, user: profile.user, profile:,
      status: status || initial.status, visibility: initial.visibility
    )
    fixture = Rails.root.join("test/fixtures/files/profile_photo.png")
    photo.image.attach(io: fixture.open, filename: "original.png", content_type: "image/png")
    photo.save!
    if processing_state == :ready
      photo.display_image.attach(io: fixture.open, filename: "display.jpg", content_type: "image/jpeg")
    end
    photo.update!(processing_state:)
    photo
  end

  def create_location(profile, latitude:, longitude:)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand, latitude:, longitude:,
      accuracy_meters: 20, source: "device", captured_at: Time.current
    )
  end
end
