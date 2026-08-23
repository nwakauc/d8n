require "test_helper"

class Api::V1::DatezaInteractionVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @viewer = create_dateza_profile(display_name: "Thandi", gender: "woman", interested_in: [ "man" ])
    @detail_target = create_dateza_profile(display_name: "Sipho", gender: "man", interested_in: [ "woman" ])
    @like_target = create_dateza_profile(display_name: "Lunga", gender: "man", interested_in: [ "woman" ])
    @pass_target = create_dateza_profile(display_name: "Themba", gender: "man", interested_in: [ "woman" ])
    @matched_target = create_dateza_profile(display_name: "Mandla", gender: "man", interested_in: [ "woman" ])
    @new_chat_target = create_dateza_profile(display_name: "Kagiso", gender: "man", interested_in: [ "woman" ])
    @match = create_match(@viewer, @matched_target)
    @new_chat_match = create_match(@viewer, @new_chat_target)
    @conversation = Messaging::StartConversation.call(
      user: @viewer.user, brand: @brand, match_public_id: @match.public_id
    ).conversation
    @identifier = IdentityIdentifier.create!(
      user: @viewer.user, kind: :email, normalized_value: "thandi@example.com"
    )
    credential = Credential.create!(
      user: @viewer.user, identity_identifier: @identifier, kind: :password, status: :active
    )
    @token, = Session.issue!(brand: @brand, user: @viewer.user, credential:)
    host! "dateza.test"
  end

  test "an unverified DateZA member may browse Find but not full profile detail" do
    assert_difference -> { FindProfileExposure.where(viewer_profile: @viewer).count }, 1 do
      get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 1 }
    end

    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("profiles").size

    get "/api/v1/profiles/#{@detail_target.public_id}", headers: bearer_headers(@token)

    assert_verification_required
  end

  test "an unverified DateZA member cannot Like Pass or create any matching state" do
    assert_no_difference [ -> { Like.count }, -> { Match.count } ] do
      post "/api/v1/profiles/#{@like_target.public_id}/likes", headers: bearer_headers(@token)
    end
    assert_verification_required

    assert_no_difference -> { ProfilePass.count } do
      post "/api/v1/profiles/#{@pass_target.public_id}/pass", headers: bearer_headers(@token)
    end
    assert_verification_required
  end

  test "an unverified DateZA member cannot use match conversation or message interaction surfaces" do
    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_verification_required

    get "/api/v1/conversations", headers: bearer_headers(@token)
    assert_verification_required

    assert_no_difference [ -> { Conversation.count }, -> { ConversationParticipant.count } ] do
      post "/api/v1/matches/#{@new_chat_match.public_id}/conversation", headers: bearer_headers(@token)
    end
    assert_verification_required

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@token)
    assert_verification_required

    assert_no_difference -> { Message.count } do
      post "/api/v1/conversations/#{@conversation.public_id}/messages",
        headers: bearer_headers(@token), params: { body: "This must not persist" }
    end
    assert_verification_required
  end

  test "verification of the current login identifier unlocks every DateZA core interaction" do
    @identifier.update!(verified_at: Time.current)

    get "/api/v1/profiles/#{@detail_target.public_id}", headers: bearer_headers(@token)
    assert_response :success

    post "/api/v1/profiles/#{@like_target.public_id}/likes", headers: bearer_headers(@token)
    assert_response :created

    post "/api/v1/profiles/#{@pass_target.public_id}/pass", headers: bearer_headers(@token)
    assert_response :created

    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_response :success

    get "/api/v1/conversations", headers: bearer_headers(@token)
    assert_response :success

    assert_difference -> { Conversation.count }, 1 do
      post "/api/v1/matches/#{@new_chat_match.public_id}/conversation", headers: bearer_headers(@token)
    end
    assert_response :created

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@token)
    assert_response :success

    assert_difference -> { Message.count }, 1 do
      post "/api/v1/conversations/#{@conversation.public_id}/messages",
        headers: bearer_headers(@token), params: { body: "Hello" }
    end
    assert_response :created
  end

  test "a different verified identifier does not verify the identifier used by this session" do
    IdentityIdentifier.create!(
      user: @viewer.user, kind: :phone, normalized_value: "+27821234567", verified_at: Time.current
    )

    get "/api/v1/profiles/#{@detail_target.public_id}", headers: bearer_headers(@token)

    assert_verification_required
  end

  test "authentication and unfinished or suspended profile failures keep their distinct behavior" do
    get "/api/v1/profiles/#{@detail_target.public_id}"
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body).fetch("error")

    @viewer.update!(status: :draft, visibility: :hidden)
    get "/api/v1/profiles/#{@detail_target.public_id}", headers: bearer_headers(@token)
    assert_response :forbidden
    assert_equal "discoverable_profile_required", JSON.parse(response.body).fetch("error")

    @viewer.brand_membership.update!(status: :suspended)
    get "/api/v1/find", headers: bearer_headers(@token)
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body).fetch("error")
  end

  test "an unverified HookUs member is not subject to the DateZA interaction rule" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    viewer = create_basic_profile(brand: hookus, gender: "woman", interested_in: [ "man" ])
    like_target = create_basic_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])
    pass_target = create_basic_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])
    identifier = IdentityIdentifier.create!(
      user: viewer.user, kind: :email, normalized_value: "unverified-hookus@example.com"
    )
    credential = Credential.create!(user: viewer.user, identity_identifier: identifier, kind: :password)
    token, = Session.issue!(brand: hookus, user: viewer.user, credential:)
    host! "hookus.test"

    get "/api/v1/profiles/#{like_target.public_id}", headers: bearer_headers(token)
    assert_response :success

    post "/api/v1/profiles/#{like_target.public_id}/likes", headers: bearer_headers(token)
    assert_response :created

    post "/api/v1/profiles/#{pass_target.public_id}/pass", headers: bearer_headers(token)
    assert_response :created
  end

  private

  def assert_verification_required
    assert_response :forbidden
    assert_equal({ "error" => "identifier_verification_required" }, JSON.parse(response.body))
  end

  def create_dateza_profile(display_name:, gender:, interested_in:)
    profile = create_basic_profile(
      brand: @brand, display_name:, gender:, interested_in:,
      user_attributes: { first_name: display_name, last_name: "Test" },
      profile_attributes: {
        country_code: "ZA", city: "Johannesburg", bio: "A complete DateZA profile",
        smoking: "never", drinking: "occasionally"
      },
      preference_attributes: { max_distance_km: 100 }
    )
    Profiles::OptionSelections.replace!(profile:, selections: {
      relationship_intent: [ "long_term_relationship" ], has_children: [ "no" ], wants_children: [ "yes" ],
      religion_importance: [ "somewhat_important" ], social_style: [ "ambivert" ], meeting_pace: [ "few_days" ]
    })
    attach_photo(profile)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand, latitude: -26.2041, longitude: 28.0473,
      accuracy_meters: 20, source: "device", captured_at: Time.current
    )
    profile.update!(status: :active, visibility: :visible)
    assert Profiles::Completion.call(profile:).complete?, "test profile must satisfy the real DateZA completion contract"
    profile
  end

  def create_basic_profile(brand:, gender:, interested_in:, display_name: "Member", user_attributes: {},
    profile_attributes: {}, preference_attributes: {})
    user = User.create!(**user_attributes)
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible, **profile_attributes
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 60, interested_in:, **preference_attributes
    )
    profile
  end

  def attach_photo(profile)
    photo = ProfilePhoto.new(brand: profile.brand, user: profile.user, profile:, position: 0)
    bytes = Rails.root.join("test/fixtures/files/profile_photo.png").binread
    photo.image.attach(io: StringIO.new(bytes), filename: "profile.png", content_type: "image/png")
    photo.save!
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
