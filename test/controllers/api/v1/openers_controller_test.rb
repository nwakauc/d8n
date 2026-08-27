require "test_helper"

class Api::V1::OpenersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @sender = create_member(email: "sender@example.com")
    @recipient = create_member(email: "recipient@example.com")
    @sender_token, = Session.issue!(brand: @brand, user: @sender.user, credential: verified_credential(@sender))
    @recipient_token, = Session.issue!(brand: @brand, user: @recipient.user, credential: verified_credential(@recipient))
    host! "dateza.test"
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "requires authentication to send an opener" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener", params: { opener_key: "coffee_or_tea" }
    assert_response :unauthorized
  end

  test "the curated catalog is exposed on profile configuration" do
    get "/api/v1/profile/configuration", headers: auth(@sender_token)

    openers = JSON.parse(response.body).fetch("configuration").fetch("openers")
    assert_equal Profiles::DatezaProfileCatalog::ENABLED_OPENERS.sort, openers.map { |o| o.fetch("key") }.sort
    assert openers.all? { |o| o.fetch("text").present? }
  end

  test "sends a curated opener and returns a minimal pending acknowledgement" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }

    assert_response :created
    body = JSON.parse(response.body).fetch("opener")
    assert_equal "pending", body.fetch("status")
    assert body.fetch("expires_at").present?
    assert_not body.key?("message")

    hook = Hook.find_by!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient)
    assert_equal "coffee_or_tea", hook.profile_opener.key
    assert_equal hook.profile_opener.text, hook.message
  end

  test "rejects an unknown opener key and never persists freeform text" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "not_a_real_key" }

    assert_response :unprocessable_entity
    assert_equal "invalid_opener", JSON.parse(response.body).fetch("error")
    assert_equal 0, Hook.where(brand: @brand).count
  end

  test "a retired opener can no longer be sent" do
    @brand.profile_openers.kept.find_by!(key: "coffee_or_tea").update!(status: :retired)

    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }

    assert_response :unprocessable_entity
    assert_equal "invalid_opener", JSON.parse(response.body).fetch("error")
  end

  test "the sender cannot send a second opener before a reply" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
    assert_response :created

    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "weekend_plans" }
    assert_response :conflict
    assert_equal "already_hooked", JSON.parse(response.body).fetch("error")
  end

  test "full loop: recipient reply unlocks a two-way conversation" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
    hook = Hook.find_by!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient)

    post "/api/v1/openers/#{hook.public_id}/reply", headers: auth(@recipient_token), params: { message: "Coffee, always!" }
    assert_response :created
    reply_body = JSON.parse(response.body)
    conversation_id = reply_body.fetch("conversation").fetch("id")
    assert_equal "Coffee, always!", reply_body.fetch("message").fetch("body")

    get "/api/v1/conversations/#{conversation_id}/messages", headers: auth(@sender_token)
    bodies = JSON.parse(response.body).fetch("messages").pluck("body")
    assert_includes bodies, hook.profile_opener.text
    assert_includes bodies, "Coffee, always!"
  end

  test "recipient inbox shows the resolved opener text and sender profile; sender has no inbox entry" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }

    get "/api/v1/openers", headers: auth(@recipient_token)
    assert_response :success
    openers = JSON.parse(response.body).fetch("openers")
    assert_equal 1, openers.length
    assert_equal Profiles::CapabilityCatalog::OPENERS.fetch("coffee_or_tea").fetch(:text), openers.first.fetch("message")
    assert_equal @sender.public_id, openers.first.fetch("sender").fetch("id")

    get "/api/v1/openers", headers: auth(@sender_token)
    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("openers").length
  end

  test "recipient can decline and the sender cannot re-send" do
    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
    hook = Hook.find_by!(brand: @brand, sender_profile: @sender)

    post "/api/v1/openers/#{hook.public_id}/decline", headers: auth(@recipient_token)
    assert_response :no_content

    post "/api/v1/profiles/#{@recipient.public_id}/opener",
      headers: auth(@sender_token), params: { opener_key: "weekend_plans" }
    assert_response :conflict
  end

  test "enforces the same daily allowance as Hook, with a 429 and Retry-After" do
    burst_window = AbuseProtection::Policy.rules_for(:send_hook).first.window
    base = Time.current

    # Spaced past the generic burst window (see below) so this exercises only
    # Hooks::Policy's own daily allowance, not the abuse-protection layer.
    Hooks::Policy::FREE_DAILY_LIMIT.times do |i|
      travel_to(base + (i * (burst_window + 1.second))) do
        target = create_member(email: "target#{SecureRandom.hex(4)}@example.com")
        post "/api/v1/profiles/#{target.public_id}/opener",
          headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
        assert_response :created
      end
    end

    travel_to(base + (Hooks::Policy::FREE_DAILY_LIMIT * (burst_window + 1.second))) do
      target = create_member(email: "onemore@example.com")
      post "/api/v1/profiles/#{target.public_id}/opener",
        headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
      assert_response :too_many_requests
      assert_equal "hook_rate_limited", JSON.parse(response.body).fetch("error")
      assert response.headers["Retry-After"].present?
    end
  end

  test "also throttles with the generic 429 well before the daily allowance is reached" do
    limit = AbuseProtection::Policy.rules_for(:send_hook).first.limit
    assert_operator limit, :<, Hooks::Policy::FREE_DAILY_LIMIT,
      "the burst ceiling must be tighter than the daily allowance to guard anything"

    freeze_time do
      limit.times do
        target = create_member(email: "burst#{SecureRandom.hex(4)}@example.com")
        post "/api/v1/profiles/#{target.public_id}/opener",
          headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
        assert_response :created
      end

      target = create_member(email: "onemoreburst@example.com")
      post "/api/v1/profiles/#{target.public_id}/opener",
        headers: auth(@sender_token), params: { opener_key: "coffee_or_tea" }
      assert_response :too_many_requests
      assert_equal "rate_limited", JSON.parse(response.body).fetch("error")
    end
  end

  private

  def create_member(email:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name: "Member",
      gender: "woman", birthdate: 28.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand: @brand, user:, profile:, min_age: 18, max_age: 60, interested_in: %w[man woman non_binary])
    IdentityIdentifier.create!(user:, kind: :email, normalized_value: email, verified_at: Time.current)
    profile
  end

  def verified_credential(profile)
    identifier = IdentityIdentifier.kept.contact.find_by!(user: profile.user)
    Credential.create!(user: profile.user, identity_identifier: identifier, kind: :password)
  end
end
