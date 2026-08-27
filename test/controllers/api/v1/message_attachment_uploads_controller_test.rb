require "test_helper"

class Api::V1::MessageAttachmentUploadsControllerTest < ActionDispatch::IntegrationTest
  teardown do
    ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil }
  end

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @conversation = conversation_between(@ada, @sam)
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      params: intent_params(media_kind: "image")
    assert_response :unauthorized
  end

  test "a participant gets a short-lived direct upload authorization for an image" do
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
        headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    end
    assert_response :created
    upload = JSON.parse(response.body).fetch("upload")
    assert upload.fetch("signed_id").present?
    assert upload.fetch("url").present?
    assert_equal "image", upload.fetch("media_kind")
    assert_no_match(/access_key|secret/i, response.body)
  end

  test "a participant gets a direct upload authorization for a video" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token),
      params: intent_params(media_kind: "video", content_type: "video/mp4", bytes: build_test_mp4_bytes)
    assert_response :created
    upload = JSON.parse(response.body).fetch("upload")
    assert_equal "video", upload.fetch("media_kind")
    assert_equal Messaging::MessageAttachmentUpload::MAX_FILE_SIZE.fetch("video"), upload.fetch("byte_size_limit")
  end

  test "the object key is scoped under the sender's user id and the conversation, never the recipient" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    blob = ActiveStorage::Blob.last

    assert_equal "brands/#{@brand.slug}/users/#{@ada.user.id}/conversations/#{@conversation.public_id}",
      blob.key.split("/attachments/").first
    assert_no_match(/#{@sam.user.id}/, blob.key)
  end

  test "an outsider cannot request an upload authorization" do
    outsider = create_profile(brand: @brand)
    outsider_token, = Session.issue!(brand: @brand, user: outsider.user)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
        headers: bearer_headers(outsider_token), params: intent_params(media_kind: "image")
    end
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "an unmatched (ended) conversation refuses new upload authorizations" do
    @conversation.match.update!(status: :ended)

    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "rejects an unsupported content type for the declared media kind" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image", content_type: "image/gif")
    assert_response :unprocessable_entity
    assert_equal "unsupported_content_type", JSON.parse(response.body).fetch("error")
  end

  test "rejects a byte_size beyond the technical ceiling for the media kind" do
    over_ceiling = Messaging::MessageAttachmentUpload::MAX_FILE_SIZE.fetch("video") + 1
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token),
      params: intent_params(media_kind: "video", content_type: "video/mp4", byte_size: over_ceiling)
    assert_response :unprocessable_entity
    assert_equal "invalid_byte_size", JSON.parse(response.body).fetch("error")
  end

  test "rejects an unknown media kind" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "audio")
    assert_response :unprocessable_entity
    assert_equal "invalid_media_kind", JSON.parse(response.body).fetch("error")
  end

  test "not configured for a brand that has no D8N platform contract at all" do
    other = Brand.create!(slug: "unregistered-brand", name: "Unregistered")
    BrandDomain.create!(brand: other, host: "unregistered-brand.test")
    host! "unregistered-brand.test"
    viewer = create_profile(brand: other)
    token, = Session.issue!(brand: other, user: viewer.user)

    post "/api/v1/conversations/#{SecureRandom.uuid}/attachments/uploads",
      headers: bearer_headers(token), params: intent_params(media_kind: "image")
    assert_response :not_found
    assert_equal "brand_not_configured", JSON.parse(response.body).fetch("error")
  end

  test "excessive upload-intent requests are rate limited" do
    limit = AbuseProtection::Policy.rules_for(:chat_media_upload_intent).find { |r| r.name == "burst" }.limit
    limit.times do
      post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
        headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
      assert_response :created
    end

    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    assert_response :too_many_requests
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def intent_params(media_kind:, content_type: nil, bytes: nil, byte_size: nil)
    content_type ||= media_kind == "video" ? "video/mp4" : "image/jpeg"
    bytes ||= media_kind == "video" ? build_test_mp4_bytes : build_test_jpeg_bytes
    {
      media_kind:, content_type:,
      byte_size: byte_size || bytes.bytesize,
      checksum: Digest::MD5.base64digest(bytes),
      filename: "attachment"
    }
  end

  def conversation_between(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    match = Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
    Messaging::StartConversation.call(user: first.user, brand: first.brand, match_public_id: match.public_id).conversation
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
