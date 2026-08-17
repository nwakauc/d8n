require "test_helper"

class Api::V1::Admin::SuspensionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    @sam_token, = Session.issue!(brand: @brand, user: @sam.user)
    @admin, @admin_token = create_admin(brand: @brand)
    host! "hookus.test"
  end

  # --- authorization ---------------------------------------------------------

  test "unauthenticated and non-moderator callers cannot enforce" do
    post suspend_path(@sam)
    assert_response :unauthorized

    post suspend_path(@sam), headers: bearer_headers(@ada_token)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).fetch("error")
  end

  test "a moderator assigned to another brand cannot enforce here" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    _admin, token = create_admin(brand: @brand, assign_brand: other_brand)

    post suspend_path(@sam), headers: bearer_headers(token)
    assert_response :forbidden
  end

  test "a cross-brand or unknown target is not disclosed" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    foreign = create_profile(brand: other_brand)

    [ foreign.public_id, SecureRandom.uuid ].each do |profile_id|
      post "/api/v1/admin/profiles/#{profile_id}/suspension", headers: bearer_headers(@admin_token)
      assert_response :not_found
      assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  # --- suspension state + sessions ------------------------------------------

  test "suspension changes membership state, records enforcement, and is audited" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.account_suspended").count }, 1 do
      post suspend_path(@sam), headers: bearer_headers(@admin_token), params: { reason: "harassment confirmed" }
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("enforcement")
    assert_equal "active", body.fetch("state")
    assert_equal @sam.public_id, body.fetch("profile_id")

    assert @sam.brand_membership.reload.suspended?
    enforcement = AccountEnforcement.sole
    assert_equal @sam.user_id, enforcement.user_id
    assert_equal @admin.id, enforcement.admin_user_id
    assert_equal "harassment confirmed", enforcement.reason

    event = SecurityEvent.where(event_type: "admin.account_suspended").last
    assert_equal @admin.id, event.metadata.fetch("admin_user_id")
    assert_equal @sam.user_id, event.metadata.fetch("target_user_id")
    assert_not_includes event.metadata.to_s, "harassment confirmed"
  end

  test "all of the target's brand sessions stop working after suspension" do
    second_token, = Session.issue!(brand: @brand, user: @sam.user)

    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :created

    [ @sam_token, second_token ].each do |token|
      get "/api/v1/me", headers: bearer_headers(token)
      assert_response :unauthorized
    end
    assert_equal 2, Session.where(user: @sam.user, brand: @brand).where.not(revoked_at: nil).count
  end

  # --- enforcement across surfaces ------------------------------------------

  test "a suspended profile disappears from discovery and cannot be interacted with" do
    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :created

    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_response :success
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    # Another user cannot interact with the suspended profile; the response is
    # neutral and never discloses the moderation reason.
    post "/api/v1/profiles/#{@sam.public_id}/likes", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a suspended user cannot act because their session is dead" do
    other = create_profile(brand: @brand)
    post suspend_path(@sam), headers: bearer_headers(@admin_token)

    post "/api/v1/profiles/#{other.public_id}/likes", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
    post "/api/v1/profiles/#{other.public_id}/pass", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
  end

  test "suspension severs an existing conversation for the counterpart without deleting history" do
    match = create_match(@ada, @sam)
    conversation = Messaging::StartConversation.call(user: @ada.user, brand: @brand, match_public_id: match.public_id).conversation
    Message.create!(brand: @brand, conversation:, sender_profile: @sam, body: "hi Ada")

    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :created

    # Counterpart can no longer read or send in that conversation.
    get "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

    # History is retained server-side (suspension is not deletion).
    assert_equal 1, conversation.messages.count
  end

  # --- report linkage + separation ------------------------------------------

  test "an enforcement can reference the originating report without changing report state" do
    report = Report.create!(brand: @brand, reporter_profile: @ada, reported_profile: @sam, reason: :harassment)

    post suspend_path(@sam), headers: bearer_headers(@admin_token), params: { report_id: report.id }
    assert_response :created
    assert_equal report.id, AccountEnforcement.sole.report_id
    # Enforcing does not touch the report's own lifecycle.
    assert report.reload.status_open?
  end

  test "an unknown report link is rejected" do
    post suspend_path(@sam), headers: bearer_headers(@admin_token), params: { report_id: 999_999 }
    assert_response :unprocessable_entity
    assert_equal "invalid_report", JSON.parse(response.body).fetch("error")
    assert_not @sam.brand_membership.reload.suspended?
  end

  test "actioning a report never suspends and suspending never actions a report" do
    report = Report.create!(brand: @brand, reporter_profile: @ada, reported_profile: @sam, reason: :spam)

    # Moderating the report leaves the account active.
    patch "/api/v1/admin/reports/#{report.id}", headers: bearer_headers(@admin_token), params: { status: "reviewing" }
    patch "/api/v1/admin/reports/#{report.id}", headers: bearer_headers(@admin_token), params: { status: "actioned" }
    assert_not @sam.brand_membership.reload.suspended?
    assert_equal 0, AccountEnforcement.count

    # Suspending leaves the (already actioned) report as it was.
    post suspend_path(@sam), headers: bearer_headers(@admin_token), params: { report_id: report.id }
    assert_response :created
    assert report.reload.status_actioned?
  end

  # --- idempotency / conflict ------------------------------------------------

  test "a repeated suspension is a conflict, not a corruption" do
    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :created

    assert_no_difference -> { AccountEnforcement.count } do
      post suspend_path(@sam), headers: bearer_headers(@admin_token)
    end
    assert_response :conflict
    assert_equal "already_suspended", JSON.parse(response.body).fetch("error")
  end

  # --- reinstatement ---------------------------------------------------------

  test "reinstatement reactivates membership and reverts the enforcement" do
    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    enforcement = AccountEnforcement.sole

    assert_difference -> { SecurityEvent.where(event_type: "admin.account_reinstated").count }, 1 do
      delete suspend_path(@sam), headers: bearer_headers(@admin_token)
    end
    assert_response :success
    assert_equal "reverted", JSON.parse(response.body).dig("enforcement", "state")

    assert @sam.brand_membership.reload.active?
    assert enforcement.reload.reverted?
    assert_equal @admin.id, enforcement.reverted_by_admin_user_id
  end

  test "reinstating a profile that is not suspended is a conflict" do
    delete suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :conflict
    assert_equal "not_suspended", JSON.parse(response.body).fetch("error")
  end

  test "reinstatement restores only membership, not revoked sessions" do
    post suspend_path(@sam), headers: bearer_headers(@admin_token)
    delete suspend_path(@sam), headers: bearer_headers(@admin_token)
    assert_response :success

    # The old session stays dead; the user must log in again.
    get "/api/v1/me", headers: bearer_headers(@sam_token)
    assert_response :unauthorized

    # A fresh session works again.
    fresh_token, = Session.issue!(brand: @brand, user: @sam.user)
    get "/api/v1/me", headers: bearer_headers(fresh_token)
    assert_response :success
  end

  # --- centerpiece -----------------------------------------------------------

  test "the full report-to-enforcement loop removes a bad actor without disclosure" do
    # A non-matched observer isolates suspension's effect on discovery (a match
    # would exclude Sam from Ada's feed regardless).
    observer = create_profile(brand: @brand, display_name: "Obs")
    observer_token, = Session.issue!(brand: @brand, user: observer.user)
    match = create_match(@ada, @sam)
    conversation = Messaging::StartConversation.call(user: @ada.user, brand: @brand, match_public_id: match.public_id).conversation
    second_token, = Session.issue!(brand: @brand, user: @sam.user)

    # Sam is active: discoverable by the observer and can message Ada.
    get "/api/v1/discovery", headers: bearer_headers(observer_token)
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id
    post "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@sam_token), params: { body: "hey" }
    assert_response :created

    # Ada reports Sam; moderator reviews then enforces.
    report = Report.create!(brand: @brand, reporter_profile: @ada, reported_profile: @sam, reason: :harassment)
    patch "/api/v1/admin/reports/#{report.id}", headers: bearer_headers(@admin_token), params: { status: "reviewing" }
    post suspend_path(@sam), headers: bearer_headers(@admin_token), params: { reason: "abuse", report_id: report.id }
    assert_response :created

    # Both of Sam's sessions are dead.
    [ @sam_token, second_token ].each do |token|
      get "/api/v1/me", headers: bearer_headers(token)
      assert_response :unauthorized
    end

    # Sam is gone from the observer's discovery and cannot message Ada; nothing
    # leaks the reason.
    get "/api/v1/discovery", headers: bearer_headers(observer_token)
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    post "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@sam_token), params: { body: "still here" }
    assert_response :unauthorized

    get "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
    assert_not_includes response.body, "abuse"
  end

  private

  def suspend_path(profile)
    "/api/v1/admin/profiles/#{profile.public_id}/suspension"
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ])
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end

  def create_admin(brand:, assign_brand: nil, role_name: "moderator")
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: role_name)
    AdminAssignment.create!(admin_user:, brand: assign_brand || brand, admin_role: role, status: :active)
    token, = Session.issue!(brand:, user:)
    [ admin_user, token ]
  end
end
