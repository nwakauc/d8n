require "test_helper"

class MessageAttachmentTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @conversation = conversation_between(@ada, @sam)
  end

  test "a text-only message needs no attachment" do
    message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "hi")
    assert message.persisted?
  end

  test "a message with neither body nor an attachment is invalid" do
    message = Message.new(brand: @brand, conversation: @conversation, sender_profile: @ada, body: nil)
    assert_not message.valid?
    assert_includes message.errors[:base], "message must have a body or at least one attachment"
  end

  test "a media-only message (nil body, one attachment) is valid" do
    message = Message.new(brand: @brand, conversation: @conversation, sender_profile: @ada, body: nil)
    message.message_attachments << build_image_attachment
    assert message.save
  end

  test "an image is not deliverable until ready, rendition, AND download_rendition all exist" do
    message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "photo")
    attachment = build_image_attachment
    message.message_attachments << attachment
    message.save!

    assert_not attachment.deliverable?
    attachment.update!(processing_state: :ready)
    assert_not attachment.reload.deliverable?, "ready with no rendition attached is still not deliverable"

    attachment.rendition.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "display.jpg", content_type: "image/jpeg")
    assert_not attachment.deliverable?, "ready with a rendition but no download_rendition is still not deliverable"

    attachment.download_rendition.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "download.jpg", content_type: "image/jpeg")
    assert attachment.deliverable?
  end

  test "a video is not deliverable until ready, rendition, AND a server poster exist" do
    message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "clip")
    attachment = MessageAttachment.new(brand: @brand, media_kind: :video, position: 0, processing_state: :pending)
    attachment.original.attach(io: StringIO.new("fake"), filename: "original.mp4", content_type: "video/mp4")
    message.message_attachments << attachment
    message.save!

    attachment.update!(processing_state: :ready)
    attachment.rendition.attach(io: StringIO.new("fake"), filename: "playback.mp4", content_type: "video/mp4")
    assert_not attachment.reload.deliverable?, "ready with a rendition but no poster is still not deliverable"

    attachment.poster.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "poster.jpg", content_type: "image/jpeg")
    assert attachment.deliverable?
  end

  test "a deleted attachment is never deliverable regardless of processing state" do
    message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "photo")
    attachment = build_image_attachment
    message.message_attachments << attachment
    message.save!
    attachment.update!(processing_state: :ready)
    attachment.rendition.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "display.jpg", content_type: "image/jpeg")
    attachment.download_rendition.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "download.jpg", content_type: "image/jpeg")
    attachment.update!(deleted_at: Time.current)

    assert_not attachment.deliverable?
  end

  private

  def build_image_attachment
    attachment = MessageAttachment.new(brand: @brand, media_kind: :image, position: 0, processing_state: :pending)
    attachment.original.attach(io: StringIO.new(build_test_jpeg_bytes), filename: "original.jpg", content_type: "image/jpeg")
    attachment
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
