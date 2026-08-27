require "test_helper"
require_relative "../../../support/exif_jpeg"

# D8N Chat Media: image/video attachments on messages. Text-only behavior is
# covered by messages_controller_test.rb, unchanged by this feature; this file
# covers the media-specific send/view/download/delete/report/auth matrix.
class Api::V1::MessagesMediaControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil }
  end

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @conversation = conversation_between(@ada, @sam)
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    @sam_token, = Session.issue!(brand: @brand, user: @sam.user)
    host! "hookus.test"
  end

  # ---- send: text / media / mixed combinations ---------------------------

  test "an image-only message (nil body) is accepted and delivered" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")

    assert_difference -> { Message.count } => 1, -> { MessageAttachment.count } => 1 do
      send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    end
    assert_response :created
    message = JSON.parse(response.body).fetch("message")
    assert_nil message.fetch("body")
    attachment = message.fetch("attachments").sole
    assert_equal "image", attachment.fetch("media_kind")
    assert_equal "pending", attachment.fetch("processing_state")
    assert_not attachment.key?("view_url"), "not deliverable until processing completes"

    perform_enqueued_jobs
    get_messages(@ada_token)
    ready = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert_equal "ready", ready.fetch("processing_state")
    assert ready.fetch("view_url").present?
    assert ready.fetch("download_url").present?
    assert_not_equal ready.fetch("view_url"), ready.fetch("download_url")
  end

  test "a video-only message is accepted, validated, and delivered" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video")

    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    assert_response :created
    perform_enqueued_jobs

    get_messages(@ada_token)
    attachment = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert_equal "video", attachment.fetch("media_kind")
    assert_equal "ready", attachment.fetch("processing_state")
    assert attachment.fetch("view_url").present?
    assert attachment.fetch("download_url").present?
    assert_in_delta 1.0, attachment.fetch("duration_seconds"), 0.2
  end

  test "text + image and text + video both persist body and attachment together" do
    image_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, body: "check this out", attachment_uploads: [ { signed_id: image_id, media_kind: "image" } ])
    assert_response :created
    assert_equal "check this out", JSON.parse(response.body).dig("message", "body")

    video_id = upload_and_complete(@ada_token, media_kind: "video")
    send_message(@ada_token, body: "and this", attachment_uploads: [ { signed_id: video_id, media_kind: "video" } ])
    assert_response :created
    assert_equal "and this", JSON.parse(response.body).dig("message", "body")
  end

  test "existing text-only behavior is unchanged" do
    send_message(@ada_token, body: "just text")
    assert_response :created
    assert_empty JSON.parse(response.body).dig("message", "attachments")
  end

  test "a message with neither body nor attachments is rejected" do
    send_message(@ada_token, body: "")
    assert_response :unprocessable_entity
    assert_equal "message_blank", JSON.parse(response.body).fetch("error")
  end

  test "a video poster is attached and returned when supplied" do
    video_id = upload_and_complete(@ada_token, media_kind: "video")
    poster_id = upload_and_complete(@ada_token, media_kind: "image")

    send_message(@ada_token,
      attachment_uploads: [ { signed_id: video_id, media_kind: "video", poster_signed_id: poster_id } ])
    assert_response :created
    perform_enqueued_jobs

    get_messages(@ada_token)
    attachment = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert attachment.fetch("poster_url").present?
  end

  test "a video with no client-supplied poster still gets a server-generated poster_url" do
    video_id = upload_and_complete(@ada_token, media_kind: "video")
    send_message(@ada_token, attachment_uploads: [ { signed_id: video_id, media_kind: "video" } ])
    perform_enqueued_jobs

    get_messages(@ada_token)
    attachment = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert attachment.fetch("poster_url").present?, "the poster is server-generated, never optional"
  end

  test "a client-supplied poster is not the production source of truth: the server poster always wins" do
    video_id = upload_and_complete(@ada_token, media_kind: "video")
    poster_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token,
      attachment_uploads: [ { signed_id: video_id, media_kind: "video", poster_signed_id: poster_id } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")

    client_poster_blob_id = MessageAttachment.find_by(public_id: attachment_id).poster.blob.id
    perform_enqueued_jobs

    server_poster_blob_id = MessageAttachment.find_by(public_id: attachment_id).reload.poster.blob.id
    assert_not_equal client_poster_blob_id, server_poster_blob_id
  end

  # ---- video playback compatibility (D8N Chat Media 1.1) -------------------

  test "an H.264/AAC MP4 needs no transcode: the rendition is byte-identical to the original" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video", bytes: build_test_h264_mp4_bytes)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    assert attachment.processing_ready?
    assert_equal attachment.original.blob.id, attachment.rendition.blob.id
  end

  test "an HEVC upload is transcoded into a distinct browser-compatible H.264/AAC rendition" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video", bytes: build_test_hevc_mp4_bytes)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    get_messages(@ada_token)
    payload = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert_equal "ready", payload.fetch("processing_state")
    assert payload.fetch("view_url").present?

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    assert_not_equal attachment.original.blob.id, attachment.rendition.blob.id
    assert_equal "video/mp4", attachment.rendition.blob.content_type
  end

  test "a MOV upload produces a compatible MP4 playback rendition" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video",
      bytes: build_test_h264_mov_bytes, content_type: "video/quicktime")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    assert attachment.processing_ready?
    assert_equal "video/mp4", attachment.rendition.blob.content_type
    get_messages(@ada_token)
    payload = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert payload.fetch("view_url").present?, "MOV input must still end up playable"
  end

  test "a real transcode failure marks the attachment failed and never exposes a broken playable attachment" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video", bytes: build_test_hevc_mp4_bytes)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])

    stub_method(Media::VideoProcessor, :call, ->(_bytes) { raise Media::VideoProcessor::TranscodeFailed, "boom" }) do
      perform_enqueued_jobs
    end

    get_messages(@ada_token)
    payload = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert_equal "failed", payload.fetch("processing_state")
    assert_not payload.key?("view_url")
    assert_not payload.key?("download_url")
    assert_not payload.key?("poster_url")
  end

  # ---- image download privacy (D8N Chat Media 1.1) --------------------------

  test "a downloaded image never carries EXIF/GPS metadata, unlike the retained original" do
    raw = ExifJpeg.with_gps
    assert raw.include?("Exif"), "the fixture must genuinely carry EXIF so this is a real proof"

    signed_id = upload_and_complete(@ada_token, media_kind: "image", bytes: raw)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    assert attachment.original.download.include?("Exif"), "the retained original still legitimately carries EXIF"

    downloaded_bytes = attachment.download_rendition.download
    refute downloaded_bytes.include?("Exif"), "the recipient's download must never carry EXIF metadata"
    refute downloaded_bytes.include?("\xFF\xE1".b), "the recipient's download must carry no APP1 metadata segment"
    decoded = Vips::Image.new_from_buffer(downloaded_bytes, "")
    assert_empty decoded.get_fields.grep(/gps/i), "download must expose no GPS fields"
  end

  test "download_url is sourced from the sanitized rendition, not the raw original" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    get_messages(@ada_token)
    payload = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole

    assert_no_match(/#{Regexp.escape(attachment.original.blob.key)}/, payload.fetch("download_url"))
  end

  test "a downloaded image is higher fidelity than the inline view rendition" do
    large = Vips::Image.black(4000, 3000).add([ 80 ]).cast("uchar").write_to_buffer(".jpg")
    signed_id = upload_and_complete(@ada_token, media_kind: "image", bytes: large)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    perform_enqueued_jobs

    attachment = MessageAttachment.find_by(public_id: attachment_id)
    view_dimensions = Vips::Image.new_from_buffer(attachment.rendition.download, "")
    download_dimensions = Vips::Image.new_from_buffer(attachment.download_rendition.download, "")
    assert_operator [ download_dimensions.width, download_dimensions.height ].max, :>,
      [ view_dimensions.width, view_dimensions.height ].max
  end

  test "multiple attachments on one message are ordered and each delivered independently" do
    ids = 3.times.map { upload_and_complete(@ada_token, media_kind: "image") }
    send_message(@ada_token, attachment_uploads: ids.map { |id| { signed_id: id, media_kind: "image" } })
    assert_response :created
    perform_enqueued_jobs

    get_messages(@ada_token)
    attachments = JSON.parse(response.body).fetch("messages").sole.fetch("attachments")
    assert_equal 3, attachments.size
    assert attachments.all? { |a| a.fetch("processing_state") == "ready" }
  end

  test "exceeding the per-message attachment count is rejected" do
    ids = (Messaging::MessageAttachmentUpload::MAX_ATTACHMENTS_PER_MESSAGE + 1).times.map do
      upload_and_complete(@ada_token, media_kind: "image")
    end

    send_message(@ada_token, attachment_uploads: ids.map { |id| { signed_id: id, media_kind: "image" } })
    assert_response :unprocessable_entity
    assert_equal "too_many_attachments", JSON.parse(response.body).fetch("error")
  end

  test "a corrupt video fails processing and is never exposed as ready" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video", bytes: build_test_mp4_bytes[0, 40])
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    assert_response :created
    perform_enqueued_jobs

    get_messages(@ada_token)
    attachment = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert_equal "failed", attachment.fetch("processing_state")
    assert_not attachment.key?("view_url")
  end

  test "an unsupported video codec is rejected during finalize-time container sniff or async processing" do
    unsupported = build_test_mp4_bytes(codec: "vp09")
    signed_id = upload_and_complete(@ada_token, media_kind: "video", bytes: unsupported)
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    assert_response :created
    perform_enqueued_jobs

    attachment = MessageAttachment.last
    assert attachment.processing_failed?
  end

  test "an already-attached blob cannot be reused for a second message" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    assert_response :created

    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    assert_response :unprocessable_entity
    assert_equal "upload_already_used", JSON.parse(response.body).fetch("error")
  end

  test "an unverified/never-uploaded signed_id is rejected" do
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    signed_id = JSON.parse(response.body).fetch("upload").fetch("signed_id")
    # Deliberately never uploaded to the storage service.

    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    assert_response :unprocessable_entity
    assert_equal "upload_not_found", JSON.parse(response.body).fetch("error")
  end

  test "an unregistered brand fails closed rather than silently allowing media uploads" do
    other = Brand.create!(slug: "media-off", name: "Media Off")
    BrandDomain.create!(brand: other, host: "media-off.test")
    a = create_profile(brand: other)
    b = create_profile(brand: other)
    conversation = conversation_between(a, b)
    token, = Session.issue!(brand: other, user: a.user)
    host! "media-off.test"

    post "/api/v1/conversations/#{conversation.public_id}/attachments/uploads",
      headers: bearer_headers(token), params: intent_params(media_kind: "image")
    assert_response :not_found
  end

  # ---- authorization matrix ------------------------------------------------

  test "a third-party member cannot view or send media in someone else's conversation" do
    outsider = create_profile(brand: @brand)
    outsider_token, = Session.issue!(brand: @brand, user: outsider.user)
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])

    get_messages(outsider_token)
    assert_response :not_found
  end

  test "blocking makes attachment upload and send unavailable in both directions" do
    Trust::BlockProfile.call(user: @ada.user, brand: @brand, target_public_id: @sam.public_id)

    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    assert_response :not_found

    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@sam_token), params: intent_params(media_kind: "image")
    assert_response :not_found
  end

  test "after unmatch, attachment upload, send, and message retrieval are all unavailable" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    perform_enqueued_jobs
    @conversation.match.update!(status: :ended)

    get_messages(@ada_token)
    assert_response :not_found

    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(@ada_token), params: intent_params(media_kind: "image")
    assert_response :not_found

    new_signed_id_attempt = upload_and_complete(@sam_token, media_kind: "image") rescue nil
    assert_nil new_signed_id_attempt, "an ended match must refuse a fresh upload intent entirely"
  end

  test "a cross-brand conversation is never reachable for media" do
    other = Brand.create!(slug: "dateza", name: "DateZA")
    BrandDomain.create!(brand: other, host: "dateza.test")
    a = create_profile(brand: other)
    b = create_profile(brand: other)
    foreign_conversation = conversation_between(a, b)

    get "/api/v1/conversations/#{foreign_conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
  end

  # ---- delete ---------------------------------------------------------------

  test "the sender can delete their own attachment; it becomes unavailable to the recipient" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    perform_enqueued_jobs
    message_id = JSON.parse(response.body).dig("message", "id")
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")

    delete "/api/v1/conversations/#{@conversation.public_id}/messages/#{message_id}/attachments/#{attachment_id}",
      headers: bearer_headers(@ada_token)
    assert_response :success
    assert JSON.parse(response.body).dig("attachment", "deleted")

    get_messages(@sam_token)
    entry = JSON.parse(response.body).fetch("messages").sole.fetch("attachments").sole
    assert entry.fetch("deleted")
    assert_not entry.key?("view_url")
    assert_not entry.key?("download_url")
  end

  test "the recipient cannot delete the sender's attachment" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    message_id = JSON.parse(response.body).dig("message", "id")
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")

    delete "/api/v1/conversations/#{@conversation.public_id}/messages/#{message_id}/attachments/#{attachment_id}",
      headers: bearer_headers(@sam_token)
    assert_response :not_found
    assert MessageAttachment.find_by(public_id: attachment_id).kept?
  end

  test "deleting an attachment purges the underlying blob(s)" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    perform_enqueued_jobs
    message_id = JSON.parse(response.body).dig("message", "id")
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")
    attachment = MessageAttachment.find_by(public_id: attachment_id)
    original_key = attachment.original.blob.key

    delete "/api/v1/conversations/#{@conversation.public_id}/messages/#{message_id}/attachments/#{attachment_id}",
      headers: bearer_headers(@ada_token)
    perform_enqueued_jobs

    service = ActiveStorage::Blob.service
    assert_not service.exist?(original_key)
  end

  test "a mixed text+media message keeps its text after the attachment is deleted" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, body: "look", attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    message_id = JSON.parse(response.body).dig("message", "id")
    attachment_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")

    delete "/api/v1/conversations/#{@conversation.public_id}/messages/#{message_id}/attachments/#{attachment_id}",
      headers: bearer_headers(@ada_token)

    get_messages(@ada_token)
    message = JSON.parse(response.body).fetch("messages").sole
    assert_equal "look", message.fetch("body")
    assert message.fetch("attachments").sole.fetch("deleted")
  end

  # ---- reporting --------------------------------------------------------

  test "the recipient can report an image message and evidence survives later deletion" do
    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    perform_enqueued_jobs
    message_public_id = JSON.parse(response.body).dig("message", "id")
    attachment_public_id = JSON.parse(response.body).dig("message", "attachments", 0, "id")

    post "/api/v1/reports", headers: bearer_headers(@sam_token),
      params: { target_type: "message", target_id: message_public_id, reason: "inappropriate_content" }
    assert_response :created
    report = Report.sole
    assert_equal "media", report.evidence.fetch("message_type")
    evidence_attachment = report.evidence.fetch("attachments").sole
    assert_equal attachment_public_id, evidence_attachment.fetch("attachment_public_id")
    assert_equal "image", evidence_attachment.fetch("media_kind")

    delete "/api/v1/conversations/#{@conversation.public_id}/messages/#{message_public_id}/attachments/#{attachment_public_id}",
      headers: bearer_headers(@ada_token)
    assert_response :success

    report.reload
    assert_equal attachment_public_id, report.evidence.fetch("attachments").sole.fetch("attachment_public_id"),
      "report evidence must survive the sender deleting the attachment"
  end

  test "the recipient can report a video message" do
    signed_id = upload_and_complete(@ada_token, media_kind: "video")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "video" } ])
    message_public_id = JSON.parse(response.body).dig("message", "id")

    post "/api/v1/reports", headers: bearer_headers(@sam_token),
      params: { target_type: "message", target_id: message_public_id, reason: "non_consensual_content" }
    assert_response :created
    assert_equal "video", Report.sole.evidence.dig("attachments", 0, "media_kind")
  end

  # ---- rate limiting ------------------------------------------------------

  test "excessive media sends hit the chat_media_attach ceiling in addition to send_message" do
    limit = AbuseProtection::Policy.rules_for(:chat_media_attach).find { |r| r.name == "burst" }.limit
    limit.times do
      signed_id = upload_and_complete(@ada_token, media_kind: "image")
      send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
      assert_response :created
    end

    signed_id = upload_and_complete(@ada_token, media_kind: "image")
    send_message(@ada_token, attachment_uploads: [ { signed_id:, media_kind: "image" } ])
    assert_response :too_many_requests
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def send_message(token, body: nil, attachment_uploads: nil)
    params = {}
    params[:body] = body unless body.nil?
    params[:attachment_uploads] = attachment_uploads if attachment_uploads
    post "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(token), params:
  end

  def get_messages(token)
    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(token)
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

  def upload_and_complete(token, media_kind:, bytes: nil, content_type: nil)
    bytes ||= media_kind == "video" ? build_test_h264_mp4_bytes : build_test_jpeg_bytes
    post "/api/v1/conversations/#{@conversation.public_id}/attachments/uploads",
      headers: bearer_headers(token), params: intent_params(media_kind:, bytes:, content_type:)
    return nil unless response.status == 201

    signed_id = JSON.parse(response.body).fetch("upload").fetch("signed_id")
    blob = ActiveStorage::Blob.find_signed!(signed_id)
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
    signed_id
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
