require "test_helper"

class Api::V1::Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @reporter = create_profile(brand: @brand, display_name: "Ada")
    @target = create_profile(brand: @brand, display_name: "Sam")
    @report = create_report(reporter: @reporter, reported: @target, reason: :harassment, note: "abusive dms")
    @admin, @admin_token = create_admin(brand: @brand)
    host! "hookus.test"
  end

  # --- authorization ---------------------------------------------------------

  test "unauthenticated requests are rejected" do
    get "/api/v1/admin/reports"
    assert_response :unauthorized

    get "/api/v1/admin/reports/#{@report.id}"
    assert_response :unauthorized

    patch "/api/v1/admin/reports/#{@report.id}", params: { status: "reviewing" }
    assert_response :unauthorized
  end

  test "an ordinary authenticated user cannot reach moderation" do
    user_token, = Session.issue!(brand: @brand, user: @reporter.user)

    get "/api/v1/admin/reports", headers: bearer_headers(user_token)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).fetch("error")

    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(user_token), params: { status: "reviewing" }
    assert_response :forbidden
  end

  test "an admin authenticated here but assigned to another brand cannot moderate this one" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    _admin, token = create_admin(brand: @brand, assign_brand: other_brand)

    get "/api/v1/admin/reports", headers: bearer_headers(token)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).fetch("error")
  end

  # --- listing ---------------------------------------------------------------

  test "an authorized moderator lists only their brand's reports" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    BrandDomain.create!(brand: other_brand, host: "other.test")
    other_report = create_report(
      reporter: create_profile(brand: other_brand), reported: create_profile(brand: other_brand)
    )

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token)

    assert_response :success
    ids = JSON.parse(response.body).fetch("reports").pluck("id")
    assert_includes ids, @report.id
    assert_not_includes ids, other_report.id
  end

  test "the queue is oldest-first and cursor-paginated without duplicates" do
    @report.update_columns(created_at: Time.utc(2026, 8, 17, 9, 0, 0))
    second = create_report(reporter: @reporter, reported: create_profile(brand: @brand), reason: :spam)
    second.update_columns(created_at: Time.utc(2026, 8, 17, 10, 0, 0))
    third = create_report(reporter: @reporter, reported: create_profile(brand: @brand), reason: :fake_profile)
    third.update_columns(created_at: Time.utc(2026, 8, 17, 11, 0, 0))

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { limit: 2 }
    first_page = JSON.parse(response.body)
    assert_equal [ @report.id, second.id ], first_page.fetch("reports").pluck("id")

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }
    assert_equal [ third.id ], JSON.parse(response.body).fetch("reports").pluck("id")
  end

  test "the status filter narrows the queue and rejects unknown values" do
    dismissed = create_report(reporter: @reporter, reported: create_profile(brand: @brand), status: :dismissed)

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { status: "open" }
    ids = JSON.parse(response.body).fetch("reports").pluck("id")
    assert_includes ids, @report.id
    assert_not_includes ids, dismissed.id

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { status: "not_a_status" }
    assert_response :unprocessable_entity
    assert_equal "invalid_filter", JSON.parse(response.body).fetch("error")
  end

  test "an invalid limit or cursor is rejected" do
    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { limit: 0 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { cursor: "garbage" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "the queue tolerates a since-removed reporter or target" do
    @target.update!(deleted_at: Time.current)
    @reporter.update!(deleted_at: Time.current)

    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token)

    assert_response :success
    card = JSON.parse(response.body).fetch("reports").find { |r| r.fetch("id") == @report.id }
    assert_equal @target.public_id, card.dig("reported", "id")
    assert_equal @reporter.public_id, card.dig("reporter", "id")
  end

  # --- detail ----------------------------------------------------------------

  test "a moderator inspects a report and the read is audited without leaking sensitive fields" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.report_viewed").count }, 1 do
      get "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token)
    end

    assert_response :success
    report = JSON.parse(response.body).fetch("report")
    assert_equal @report.id, report.fetch("id")
    assert_equal "harassment", report.fetch("reason")
    assert_equal "abusive dms", report.fetch("note")
    assert_equal @reporter.public_id, report.dig("reporter", "id")
    assert_equal @target.public_id, report.dig("reported", "id")

    flat = report.to_s
    %w[email phone password credential token session birthdate latitude].each do |leak|
      assert_not_includes flat, leak, "report detail leaked #{leak}"
    end

    event = SecurityEvent.where(event_type: "admin.report_viewed").last
    assert_equal @admin.id, event.metadata.fetch("admin_user_id")
    assert_equal @report.id, event.metadata.fetch("report_id")
    assert_not_includes event.metadata.to_s, "abusive dms"
  end

  test "a cross-brand or unknown report is unavailable" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    foreign = create_report(
      reporter: create_profile(brand: other_brand), reported: create_profile(brand: other_brand)
    )

    [ foreign.id, 999_999 ].each do |id|
      get "/api/v1/admin/reports/#{id}", headers: bearer_headers(@admin_token)
      assert_response :not_found
      assert_equal "report_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  test "the detail view distinguishes profile, message, and conversation report evidence" do
    profile_a_id, profile_b_id = Match.canonical_pair(@reporter.id, @target.id)
    match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    conversation = Messaging::StartConversation.call(
      user: @reporter.user, brand: @brand, match_public_id: match.public_id
    ).conversation
    message = Message.create!(brand: @brand, conversation:, sender_profile: @target, body: "abuse")

    message_report = Trust::FileReport.call(
      user: @reporter.user, brand: @brand, target_type: "message", target_id: message.public_id, reason: "harassment"
    ).report
    conversation_report = Trust::FileReport.call(
      user: @reporter.user, brand: @brand, target_type: "conversation", target_id: conversation.public_id,
      reason: "harassment"
    ).report

    get "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token)
    assert_equal "profile", JSON.parse(response.body).dig("report", "target_type")

    get "/api/v1/admin/reports/#{message_report.id}", headers: bearer_headers(@admin_token)
    body = JSON.parse(response.body).fetch("report")
    assert_equal "message", body.fetch("target_type")
    assert_equal "abuse", body.dig("evidence", "body")

    get "/api/v1/admin/reports/#{conversation_report.id}", headers: bearer_headers(@admin_token)
    body = JSON.parse(response.body).fetch("report")
    assert_equal "conversation", body.fetch("target_type")
    assert_equal [ "abuse" ], body.dig("evidence", "messages").pluck("body")
    assert_equal @target.id, body.dig("evidence", "messages").first.fetch("sender_profile_id")
  end

  # --- transitions -----------------------------------------------------------

  test "a moderator moves a report through reviewing to actioned and the decision is recorded" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.report_transitioned").count }, 1 do
      patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
        params: { status: "reviewing" }
    end
    assert_response :success
    assert_equal "reviewing", JSON.parse(response.body).dig("report", "status")

    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
      params: { status: "actioned", note: "confirmed harassment; escalated" }
    assert_response :success

    @report.reload
    assert @report.status_actioned?
    assert_equal @admin.id, @report.reviewed_by_admin_user_id
    assert @report.reviewed_at.present?
    assert_equal "confirmed harassment; escalated", @report.resolution_note

    event = SecurityEvent.where(event_type: "admin.report_transitioned").last
    assert_equal "actioned", event.metadata.fetch("to_status")
    assert_equal @admin.id, event.metadata.fetch("admin_user_id")
    assert event.metadata.fetch("has_note")
    assert_not_includes event.metadata.to_s, "confirmed harassment"
  end

  test "a moderator can dismiss an open report directly" do
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
      params: { status: "dismissed" }

    assert_response :success
    assert @report.reload.status_dismissed?
  end

  test "an invalid transition is rejected and a terminal report reports a conflict" do
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
      params: { status: "actioned" }
    assert_response :unprocessable_entity
    assert_equal "invalid_transition", JSON.parse(response.body).fetch("error")
    assert @report.reload.status_open?

    @report.update!(status: :actioned)
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
      params: { status: "reviewing" }
    assert_response :conflict
    assert_equal "report_conflict", JSON.parse(response.body).fetch("error")
  end

  test "an unknown target status is rejected" do
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token),
      params: { status: "banned" }
    assert_response :unprocessable_entity
    assert_equal "invalid_status", JSON.parse(response.body).fetch("error")
  end

  test "the update endpoint cannot mass-assign report internals" do
    original_reason = @report.reason
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token), params: {
      status: "reviewing",
      reason: "underage",
      reporter_profile_id: @target.id,
      reported_profile_id: @reporter.id,
      brand_id: 999,
      created_at: 10.years.ago.iso8601
    }

    assert_response :success
    @report.reload
    assert_equal "reviewing", @report.status
    assert_equal original_reason, @report.reason
    assert_equal @reporter.id, @report.reporter_profile_id
    assert_equal @target.id, @report.reported_profile_id
    assert_equal @brand.id, @report.brand_id
  end

  test "the full report-to-decision loop works end to end" do
    # User A already reported B in setup. Moderator reviews and resolves.
    get "/api/v1/admin/reports", headers: bearer_headers(@admin_token), params: { status: "open" }
    assert_includes JSON.parse(response.body).fetch("reports").pluck("id"), @report.id

    get "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token)
    assert_response :success

    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token), params: { status: "reviewing" }
    assert_response :success
    patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token), params: { status: "dismissed", note: "no violation" }
    assert_response :success

    assert @report.reload.status_dismissed?
    assert_equal @admin.id, @report.reviewed_by_admin_user_id
    assert SecurityEvent.where(event_type: "admin.report_transitioned").where("metadata->>'to_status' = ?", "dismissed").exists?
  end

  test "moderating a report never touches user blocks" do
    assert_no_difference -> { ProfileBlock.count } do
      patch "/api/v1/admin/reports/#{@report.id}", headers: bearer_headers(@admin_token), params: { status: "dismissed" }
    end
    assert_response :success
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
  end

  def create_report(reporter:, reported:, brand: nil, reason: :spam, status: :open, note: nil)
    Report.create!(
      brand: brand || reporter.brand, reporter_profile: reporter, reported_profile: reported,
      reason:, status:, note:
    )
  end

  # An admin authenticates on `brand` (needs membership + a brand session) and is
  # granted moderation on `assign_brand` (defaults to the same brand).
  def create_admin(brand:, assign_brand: nil, role_name: "moderator")
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: role_name)
    AdminAssignment.create!(admin_user:, brand: assign_brand || brand, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
