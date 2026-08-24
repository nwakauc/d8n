require "test_helper"

# Reporting V2: content-level reporting through the generic POST /api/v1/reports.
# Profile backward-compatibility lives in reports_controller_test.rb; this file
# covers message / photo / Hook targets, evidence, duplicate/concurrency, the
# report-and-block flow, rate limiting, and cross-brand isolation.
class Api::V1::GenericReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @reporter = create_profile(brand: @brand, display_name: "Ada")
    @offender = create_profile(brand: @brand, display_name: "Sam")
    @token, = Session.issue!(brand: @brand, user: @reporter.user)
    @offender_token, = Session.issue!(brand: @brand, user: @offender.user)
    host! "hookus.test"
  end

  # ---- message reporting -------------------------------------------------

  test "a conversation participant reports a received message with sender-derived evidence" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abusive text")

    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment", details: "  keeps at it  ")
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("created")
    assert_equal "received", body.dig("report", "status")

    report = Report.sole
    assert report.target_message?
    assert_equal message.id, report.target_id
    assert_equal @offender.id, report.reported_profile_id, "responsible profile is derived from the message sender"
    assert_equal @reporter.id, report.reporter_profile_id
    assert_equal "keeps at it", report.note, "details are normalized (trimmed)"
    assert_equal "abusive text", report.evidence.fetch("body")
    assert_equal message.public_id, report.evidence.fetch("message_public_id")
  end

  test "reporting your own message is a neutral target_unavailable" do
    conversation = conversation_between(@reporter, @offender)
    mine = Message.create!(brand: @brand, conversation:, sender_profile: @reporter, body: "my own")

    assert_no_difference -> { Report.count } do
      post_report(target_type: "message", target_id: mine.public_id, reason: "spam")
    end
    assert_neutral_unavailable
  end

  test "an outsider cannot report a message from a conversation they do not belong to" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "private")
    outsider = create_profile(brand: @brand)
    outsider_token, = Session.issue!(brand: @brand, user: outsider.user)

    assert_no_difference -> { Report.count } do
      post_report(token: outsider_token, target_type: "message", target_id: message.public_id, reason: "harassment")
    end
    assert_neutral_unavailable
  end

  test "an unknown message id is a neutral target_unavailable" do
    post_report(target_type: "message", target_id: SecureRandom.uuid, reason: "spam")
    assert_neutral_unavailable
  end

  test "a message stays reportable after the sender is blocked" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "earlier abuse")
    Trust::BlockProfile.call(user: @reporter.user, brand: @brand, target_public_id: @offender.public_id)

    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
    end
    assert_response :created
  end

  test "a message stays reportable after the sender is suspended or closed" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")

    @offender.update!(status: :suspended)
    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
    end
    assert_response :created

    # Simulate closure: the offending profile is discarded but the message is
    # retained. The reporter (whose prior report resolved) can file a fresh one.
    Report.update_all(status: :dismissed)
    @offender.update!(deleted_at: Time.current)
    assert_difference -> { Report.open_reports.count } => 1 do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
    end
    assert_response :created
  end

  test "message evidence snapshots only the reported message, not surrounding history" do
    conversation = conversation_between(@reporter, @offender)
    Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "one")
    reported = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "two")
    Message.create!(brand: @brand, conversation:, sender_profile: @reporter, body: "three")

    post_report(target_type: "message", target_id: reported.public_id, reason: "harassment")
    assert_response :created
    evidence = Report.sole.evidence
    assert_equal "two", evidence.fetch("body")
    assert_not evidence.value?("one")
    assert_not evidence.value?("three")
  end

  # ---- photo reporting ---------------------------------------------------

  test "a viewer reports a visible photo with owner derived server-side and no storage leakage" do
    photo = attach_photo(@offender)

    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "profile_media", target_id: photo.public_id, reason: "non_consensual_content")
    end
    assert_response :created
    report = Report.sole
    assert report.target_profile_media?
    assert_equal photo.id, report.target_id
    assert_equal @offender.id, report.reported_profile_id
    assert_equal photo.public_id, report.evidence.fetch("photo_public_id")
    assert_empty report.evidence.keys.grep(/url|key|path/i), "evidence must not leak R2 keys, paths, or URLs"
  end

  test "a photo that is not deliverable is a neutral target_unavailable" do
    hidden = attach_photo(@offender, visibility: :hidden)
    post_report(target_type: "profile_media", target_id: hidden.public_id, reason: "inappropriate_content")
    assert_neutral_unavailable
  end

  test "a photo whose owner is not visible to the viewer is a neutral target_unavailable" do
    photo = attach_photo(@offender)
    Trust::BlockProfile.call(user: @offender.user, brand: @brand, target_public_id: @reporter.public_id)

    post_report(target_type: "profile_media", target_id: photo.public_id, reason: "inappropriate_content")
    assert_neutral_unavailable
  end

  test "a deleted photo is a neutral target_unavailable" do
    photo = attach_photo(@offender)
    photo.update!(deleted_at: Time.current)
    post_report(target_type: "profile_media", target_id: photo.public_id, reason: "inappropriate_content")
    assert_neutral_unavailable
  end

  # ---- hook reporting ----------------------------------------------------

  test "the recipient reports a Hook opener with sender-derived evidence" do
    hook = send_hook(@offender, to: @reporter, message: "gross opener")

    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "hook", target_id: hook.public_id, reason: "harassment")
    end
    assert_response :created
    report = Report.sole
    assert report.target_hook?
    assert_equal hook.id, report.target_id
    assert_equal @offender.id, report.reported_profile_id
    assert_equal "gross opener", report.evidence.fetch("opener")
  end

  test "a non-recipient cannot report a Hook" do
    hook = send_hook(@offender, to: @reporter, message: "opener")
    stranger = create_profile(brand: @brand)
    stranger_token, = Session.issue!(brand: @brand, user: stranger.user)

    assert_no_difference -> { Report.count } do
      post_report(token: stranger_token, target_type: "hook", target_id: hook.public_id, reason: "harassment")
    end
    assert_neutral_unavailable
  end

  test "a declined Hook is still reportable by its recipient" do
    hook = send_hook(@offender, to: @reporter, message: "opener")
    Hooks::DeclineHook.call(user: @reporter.user, brand: @brand, hook_public_id: hook.public_id)

    assert_difference -> { Report.count } => 1 do
      post_report(target_type: "hook", target_id: hook.public_id, reason: "harassment")
    end
    assert_response :created
  end

  # ---- duplicate / concurrency ------------------------------------------

  test "reporting the same target twice is idempotent" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")

    post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
    assert_response :created

    assert_no_difference -> { Report.count } do
      post_report(target_type: "message", target_id: message.public_id, reason: "spam")
    end
    assert_response :success
    assert_not JSON.parse(response.body).fetch("created")
  end

  test "distinct content from the same person can each be reported" do
    conversation = conversation_between(@reporter, @offender)
    message_a = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "a")
    message_b = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "b")
    photo = attach_photo(@offender)

    assert_difference -> { Report.count } => 3 do
      post_report(target_type: "message", target_id: message_a.public_id, reason: "harassment")
      post_report(target_type: "message", target_id: message_b.public_id, reason: "harassment")
      post_report(target_type: "profile_media", target_id: photo.public_id, reason: "inappropriate_content")
    end
  end

  test "the database rejects a second open report for the same content target" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")
    Report.create!(brand: @brand, reporter_profile: @reporter, reported_profile: @offender,
      target_type: :message, target_id: message.id, reason: :harassment)

    assert_raises(ActiveRecord::RecordNotUnique) do
      # Bypass validations to prove the invariant is DB-enforced, not app-only.
      Report.new(brand: @brand, reporter_profile: @reporter, reported_profile: @offender,
        target_type: :message, target_id: message.id, reason: :spam).save!(validate: false)
    end
  end

  # ---- report and block --------------------------------------------------

  test "report with block also blocks the responsible profile" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")

    assert_difference -> { Report.count } => 1, -> { ProfileBlock.kept.count } => 1 do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment", block: true)
    end
    assert_response :created
    assert JSON.parse(response.body).fetch("blocked")
    assert ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @reporter, blocked_profile: @offender)
  end

  # ---- rate limiting -----------------------------------------------------

  test "the report abuse ceiling returns a 429 with Retry-After" do
    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")
    limit = AbuseProtection::Policy.rules_for(:report_profile).find { |r| r.name == "burst" }.limit

    limit.times do
      post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
      assert_includes [ 200, 201 ], response.status
    end

    post_report(target_type: "message", target_id: message.public_id, reason: "harassment")
    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body).fetch("error")
    assert response.headers["Retry-After"].present?
  end

  # ---- validation / cross-brand isolation --------------------------------

  test "an unknown target type or reason is a 422" do
    post_report(target_type: "video", target_id: SecureRandom.uuid, reason: "spam")
    assert_response :unprocessable_entity
    assert_equal "invalid_target_type", JSON.parse(response.body).fetch("error")

    conversation = conversation_between(@reporter, @offender)
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "abuse")
    post_report(target_type: "message", target_id: message.public_id, reason: "not_a_reason")
    assert_response :unprocessable_entity
    assert_equal "invalid_reason", JSON.parse(response.body).fetch("error")
  end

  test "content from another brand is a neutral target_unavailable" do
    other = Brand.create!(slug: "other", name: "Other")
    BrandDomain.create!(brand: other, host: "other.test")
    o_a = create_profile(brand: other)
    o_b = create_profile(brand: other)
    conversation = conversation_between(o_a, o_b)
    foreign_message = Message.create!(brand: other, conversation:, sender_profile: o_b, body: "x")
    foreign_photo = attach_photo(o_b)

    post_report(target_type: "message", target_id: foreign_message.public_id, reason: "harassment")
    assert_neutral_unavailable
    post_report(target_type: "profile_media", target_id: foreign_photo.public_id, reason: "inappropriate_content")
    assert_neutral_unavailable
  end

  private

  def post_report(token: @token, **params)
    post "/api/v1/reports", headers: bearer_headers(token), params: params
  end

  def assert_neutral_unavailable
    assert_response :not_found
    assert_equal "target_unavailable", JSON.parse(response.body).fetch("error")
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def conversation_between(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    match = Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
    Messaging::StartConversation.call(user: first.user, brand: first.brand, match_public_id: match.public_id).conversation
  end

  def send_hook(sender, to:, message:)
    Hooks::SendHook.call(
      user: sender.user, brand: sender.brand, target_public_id: to.public_id,
      message:, eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
    )
    Hook.find_by!(brand: sender.brand, sender_profile: sender, recipient_profile: to)
  end

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
end
