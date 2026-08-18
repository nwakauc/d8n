require "test_helper"
require "vips"

class Api::V1::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(
      brand: @brand, gender: "woman", age: 30,
      interested_in: [ "man" ], min_age: 25, max_age: 40
    )
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    target = create_candidate

    get "/api/v1/profiles/#{target.public_id}"

    assert_response :unauthorized
  end

  test "authenticated member retrieves an eligible same-brand profile by public id" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    target = create_candidate(display_name: "Sam", bio: "Hi there", occupation: "Chef")
    Profiles::OptionSelections.replace!(profile: target, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal target.public_id, profile.fetch("id")
    assert_equal "Sam", profile.fetch("display_name")
    assert_equal "Hi there", profile.fetch("bio")
    assert_equal "Chef", profile.fetch("occupation")
    assert_equal [ "hookups" ], profile.fetch("options").fetch("intents")
  end

  test "response uses the public profile id and never internal identifiers or a compatibility payload" do
    target = create_candidate(display_name: "Sam")

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal target.public_id, profile.fetch("id")
    assert_not_equal target.id.to_s, profile.fetch("id")
    assert_match Profile::PUBLIC_ID_FORMAT, profile.fetch("id")
    # Direct access describes the person; it is not a ranking surface.
    assert_not profile.key?("compatibility")
  end

  test "includes viewer-relative status fields on the profile detail" do
    target = create_candidate(display_name: "Sam")
    IdentityIdentifier.create!(user: target.user, kind: :email, normalized_value: "sam@example.com", verified_at: Time.current)
    Session.issue!(brand: @brand, user: target.user).last.update!(last_used_at: 1.minute.ago)
    create_location(@viewer)
    create_location(target)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert profile.fetch("verified")
    assert profile.fetch("online")
    assert profile.fetch("last_active_at").present?
    # @viewer and target share create_location's coordinates, so distance floors to 1.
    assert_equal 1, profile.fetch("distance_km")
    assert_equal "available", profile.fetch("hook_state")
  end

  test "profile detail reflects a live outgoing hook as pending" do
    target = create_candidate(display_name: "Sam")
    Hooks::SendHook.call(
      user: @viewer.user, brand: @brand, target_public_id: target.public_id,
      message: "hey 🔥", strategy: Matching::Strategies::Hookus
    )

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    assert_equal "pending", JSON.parse(response.body).fetch("profile").fetch("hook_state")
  end

  test "does not expose email, phone, credentials, internal ids, or coordinates" do
    target = create_candidate(display_name: "Sam")
    create_location(target)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    %w[user_id brand_id brand_membership_id birthdate email phone latitude longitude].each do |field|
      assert_not profile.key?(field), "expected #{field} to be absent"
    end
    assert_not_includes response.body, "-33.9249"
    assert_not_includes response.body, "18.4241"
  end

  test "unknown profile id returns neutral profile_unavailable" do
    get "/api/v1/profiles/#{SecureRandom.uuid}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "malformed profile id returns the same neutral profile_unavailable" do
    get "/api/v1/profiles/not-a-uuid", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "cannot retrieve the viewer's own profile through the endpoint" do
    get "/api/v1/profiles/#{@viewer.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "wrong-brand profile returns neutral profile_unavailable" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other = create_profile(
      brand: other_brand, gender: "man", age: 30,
      interested_in: [ "woman" ], min_age: 25, max_age: 40
    )

    get "/api/v1/profiles/#{other.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "hidden profile is unavailable" do
    target = create_candidate
    target.update!(visibility: :hidden)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "inactive (draft) profile is unavailable" do
    target = create_candidate
    target.update!(status: :draft)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "suspended member is unavailable" do
    target = create_candidate
    target.brand_membership.update!(status: :suspended)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "closed / discarded profile is unavailable" do
    target = create_candidate

    Accounts::CloseAccount.call(user: target.user, brand: @brand)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "block A to B: viewer who blocked the target cannot retrieve it" do
    target = create_candidate
    ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: target)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "block B to A: target who blocked the viewer cannot be retrieved" do
    target = create_candidate
    ProfileBlock.create!(brand: @brand, blocker_profile: target, blocked_profile: @viewer)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "an ineligible viewer cannot use the endpoint" do
    @viewer.update!(status: :draft)
    target = create_candidate

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal({ "error" => "discoverable_profile_required" }, JSON.parse(response.body))
  end

  test "retrieval does not depend on mutual dating preferences (does not require ranking eligibility)" do
    # Target's preferences exclude the viewer's gender/age, so it would NOT appear
    # in the viewer's ranked discovery — yet it is still directly retrievable.
    target = create_profile(
      brand: @brand, gender: "man", age: 30,
      interested_in: [ "man" ], min_age: 25, max_age: 26, display_name: "Ranked out"
    )

    # Confirm it is genuinely absent from ranked discovery.
    get "/api/v1/discovery", headers: bearer_headers(@token)
    assert_response :success
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), target.public_id

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)
    assert_response :success
    assert_equal target.public_id, JSON.parse(response.body).fetch("profile").fetch("id")
  end

  test "returns the safe display derivative and never the raw original" do
    target = create_candidate(display_name: "Sam")
    photo = attach_photo(target, visibility: :visible, processing_state: :ready)
    raw_key = photo.image.blob.key

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("profile").fetch("photos")
    assert_equal 1, photos.size
    entry = photos.sole
    assert_equal 0, entry.fetch("position")
    assert_operator entry.fetch("url_expires_in"), :>, 0
    assert_includes entry.fetch("url"), "display.jpg"
    assert_not_includes response.body, raw_key
    assert_not_includes entry.fetch("url"), raw_key
  end

  test "fails closed: hidden, still-processing, and failed photos are not exposed" do
    target = create_candidate
    attach_photo(target, position: 0, visibility: :hidden, processing_state: :ready)
    attach_photo(target, position: 1, visibility: :visible, processing_state: :pending)
    attach_photo(target, position: 2, visibility: :visible, processing_state: :failed)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profile").fetch("photos")
  end

  test "multiple eligible photos preserve deterministic position order" do
    target = create_candidate
    attach_photo(target, position: 2, visibility: :visible, processing_state: :ready)
    attach_photo(target, position: 0, visibility: :visible, processing_state: :ready)
    attach_photo(target, position: 1, visibility: :visible, processing_state: :ready)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    positions = JSON.parse(response.body).fetch("profile").fetch("photos").pluck("position")
    assert_equal [ 0, 1, 2 ], positions
  end

  test "assembles the profile without an N+1 explosion across photos and options" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    target = create_candidate
    Profiles::OptionSelections.replace!(profile: target, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })
    3.times { |index| attach_photo(target, position: index, visibility: :visible, processing_state: :ready) }

    select_count = count_select_queries do
      get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)
    end

    assert_response :success
    # Budget guards against an N+1 that scales with photos/options. The viewer
    # status fields (verified, presence, viewer + candidate location) and the
    # viewer-relative hook state (matches/outgoing/incoming/likes) each add a
    # small *fixed* number of queries that does not grow with either.
    assert_operator select_count, :<, 30
  end

  # Centerpiece: B is discoverable by A and directly retrievable; once B blocks A
  # the identical direct request becomes neutrally unavailable, proving the direct
  # endpoint does not bypass safety.
  test "centerpiece: discoverable target is directly retrievable until it blocks the viewer" do
    target = create_candidate(display_name: "Bea")
    photo = attach_photo(target, visibility: :visible, processing_state: :ready)

    get "/api/v1/discovery", headers: bearer_headers(@token)
    assert_response :success
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), target.public_id

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)
    assert_response :success
    detail = JSON.parse(response.body).fetch("profile")
    assert_equal target.public_id, detail.fetch("id")
    assert_equal "Bea", detail.fetch("display_name")
    assert_includes detail.fetch("photos").sole.fetch("url"), "display.jpg"
    assert_not_includes response.body, photo.image.blob.key

    ProfileBlock.create!(brand: @brand, blocker_profile: target, blocked_profile: @viewer)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)
    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "detail exposes prompts and interests but never company_name or matches_only without a match" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    target = create_candidate(display_name: "Sam")
    target.update!(company_name: "Secret Corp")
    Profiles::OptionSelections.replace!(profile: target, selections: {
      "intents" => %w[ hookups ], "vibes" => %w[ chill ],
      "interests" => %w[ foodie ], "physical_affection" => %w[ high ]
    })
    Profiles::PromptAnswers.replace!(profile: target, answers: [ { "key" => "perfect_night", "answer" => "Live music." } ])

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal %w[ foodie ], profile.fetch("interests").map { |i| i.fetch("slug") }
    assert_equal [ "Live music." ], profile.fetch("prompts").map { |p| p.fetch("answer") }
    # Sensitive/owner-only data never leaks to a non-matched viewer.
    assert_not profile.key?("company_name")
    assert_not_includes response.body, "Secret Corp"
    assert_not profile.fetch("options").key?("physical_affection")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_candidate(display_name: nil, bio: nil, occupation: nil)
    profile = create_profile(
      brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ],
      min_age: 25, max_age: 40, display_name:
    )
    profile.update!(bio:, occupation:) if bio || occupation
    profile
  end

  def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:, gender:,
      birthdate: age.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:)
    profile
  end

  # Simulates a processed photo: a raw original plus (when ready) the safe
  # display derivative other users may see.
  def attach_photo(profile, position: 0, visibility: :visible, processing_state: :ready)
    jpeg = Vips::Image.black(60, 40).add([ 120 ]).cast("uchar").write_to_buffer(".jpg")
    photo = ProfilePhoto.new(brand: profile.brand, user: profile.user, profile:, position:, visibility:)
    photo.image.attach(io: StringIO.new(jpeg), filename: "original.jpg", content_type: "image/jpeg")
    photo.save!
    if processing_state.to_sym == :ready
      photo.display_image.attach(io: StringIO.new(jpeg), filename: "display.jpg", content_type: "image/jpeg")
    end
    photo.update!(processing_state:)
    photo
  end

  def create_location(profile)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand,
      latitude: -33.9249, longitude: 18.4241, accuracy_meters: 20,
      source: "device", captured_at: Time.current
    )
  end

  def count_select_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def require_only_public_options
    @brand.update!(profile_requirements: {
      profile_fields: [],
      preference_fields: [],
      collections: [],
      option_groups: %w[ intents vibes ]
    })
  end
end
