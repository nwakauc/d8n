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

  test "contact verification ignores verified non-contact identifiers" do
    target = create_candidate(display_name: "Sam")
    IdentityIdentifier.create!(
      user: target.user, kind: :oauth_provider_uid,
      normalized_value: "provider:subject", verified_at: Time.current
    )

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal false, profile.fetch("verified")
    assert_equal false, profile.dig("verification", "contact", "verified")
  end

  test "profile detail reflects a live outgoing hook as pending" do
    target = create_candidate(display_name: "Sam")
    Hooks::SendHook.call(
      user: @viewer.user, brand: @brand, target_public_id: target.public_id,
      message: "hey 🔥", eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
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
    assert entry.fetch("primary")
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

  test "fails closed when a rejected photo is otherwise visible and ready" do
    target = create_candidate
    attach_photo(target, visibility: :visible, processing_state: :ready, status: :rejected)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profile").fetch("photos")
  end

  test "a rejected or hidden ordered lead promotes the next deliverable photo" do
    target = create_candidate
    attach_photo(target, position: 0, visibility: :visible, processing_state: :ready, status: :rejected)
    attach_photo(target, position: 1, visibility: :hidden, processing_state: :ready)
    next_photo = attach_photo(target, position: 2, visibility: :visible, processing_state: :ready)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("profile").fetch("photos")
    assert_equal [ next_photo.public_id ], photos.pluck("id")
    assert photos.sole.fetch("primary")
  end

  test "multiple eligible photos preserve deterministic position order" do
    target = create_candidate
    attach_photo(target, position: 2, visibility: :visible, processing_state: :ready)
    attach_photo(target, position: 0, visibility: :visible, processing_state: :ready)
    attach_photo(target, position: 1, visibility: :visible, processing_state: :ready)

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("profile").fetch("photos")
    positions = photos.pluck("position")
    assert_equal [ 0, 1, 2 ], positions
    assert_equal [ true, false, false ], photos.pluck("primary")
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

  test "DateZA detail includes existing compatibility and explicit contact verification without private inputs" do
    brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand:)
    BrandDomain.create!(brand:, host: "dateza.test")
    viewer = create_profile(
      brand:, gender: "woman", age: 30, interested_in: [ "man" ],
      min_age: 25, max_age: 40, display_name: "Viewer"
    )
    target = create_profile(
      brand:, gender: "man", age: 31, interested_in: [ "woman" ],
      min_age: 25, max_age: 40, display_name: "Target"
    )
    target.update!(
      company_name: "Private Corp", looking_for_text: "Something lasting",
      job_title: "Engineer", occupation: "Software", school_or_institution: "UCT",
      height_cm: 181, languages: [ { "code" => "en", "primary" => true } ],
      smoking: "never", drinking: "occasionally", fitness: "regularly"
    )
    shared = {
      relationship_intent: [ "long_term_relationship" ],
      has_children: [ "no" ], wants_children: [ "yes" ],
      religion_importance: [ "somewhat_important" ], social_style: [ "ambivert" ],
      meeting_pace: [ "few_days" ], religion: [ "christian" ],
      education_level: [ "postgraduate" ], diet: [ "anything" ], pets: [ "dog" ],
      sleep_schedule: [ "early_bird" ], travel_frequency: [ "sometimes" ],
      communication_style: [ "mixed" ], planning_style: [ "planner" ],
      interests: %w[ hiking live_music ]
    }
    Profiles::OptionSelections.replace!(profile: viewer, selections: shared)
    Profiles::OptionSelections.replace!(profile: target, selections: shared)
    viewer.update!(status: :active, visibility: :visible)
    target.update!(status: :active, visibility: :visible)
    IdentityIdentifier.create!(
      user: target.user, kind: :email, normalized_value: "target@example.com", verified_at: Time.current
    )
    viewer_identifier = IdentityIdentifier.create!(
      user: viewer.user, kind: :email, normalized_value: "viewer@example.com", verified_at: Time.current
    )
    credential = Credential.create!(
      user: viewer.user, identity_identifier: viewer_identifier, kind: :password, status: :active
    )
    token, = Session.issue!(brand:, user: viewer.user, credential:)
    host! "dateza.test"

    get "/api/v1/profiles/#{target.public_id}", headers: bearer_headers(token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal "Something lasting", profile.fetch("looking_for_text")
    assert_equal "Engineer", profile.fetch("job_title")
    assert_equal "Software", profile.fetch("occupation")
    assert_equal "UCT", profile.fetch("school_or_institution")
    assert_equal 181, profile.fetch("height_cm")
    assert_equal "en", profile.fetch("languages").sole.fetch("code")
    assert_equal %w[ live_music hiking ], profile.fetch("interests").pluck("slug")
    %w[relationship_intent social_style meeting_pace education_level diet pets sleep_schedule
      travel_frequency communication_style planning_style interests].each do |key|
      assert profile.fetch("options").key?(key), "expected public DateZA option #{key}"
    end
    assert_equal "dateza_v1", profile.fetch("compatibility").fetch("version")
    assert_equal true, profile.dig("verification", "contact", "verified")
    assert_not profile.key?("company_name")
    assert_not profile.fetch("options").key?("has_children")
    assert_not profile.fetch("options").key?("wants_children")
    assert_not profile.fetch("options").key?("religion")
    assert_not profile.fetch("options").key?("religion_importance")
    assert_not profile.fetch("verification").key?("realme")
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
  def attach_photo(profile, position: 0, visibility: :visible, processing_state: :ready, status: :pending_review)
    jpeg = Vips::Image.black(60, 40).add([ 120 ]).cast("uchar").write_to_buffer(".jpg")
    photo = ProfilePhoto.new(brand: profile.brand, user: profile.user, profile:, position:, visibility:, status:)
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
