class Message < ApplicationRecord
  # Beta chat is plain text with a bounded length. The limit is generous enough
  # for real conversation but small enough to blunt payload abuse; it is measured
  # in Unicode codepoints after NFC normalization (see Messaging::SendMessage).
  MAX_BODY_LENGTH = 2_000

  belongs_to :brand
  belongs_to :conversation
  belongs_to :sender_profile, class_name: "Profile"
  belongs_to :reply_to_message, class_name: "Message", optional: true

  # Ordered by default so eager-loaded association access (Messaging::MessageList,
  # Messaging::MessageSerializer) never re-queries just to sort — deleted
  # attachments stay in this association (shown as a "removed" state in the
  # transcript, not hidden), so this is deliberately NOT scoped to `kept`.
  has_many :message_attachments, -> { order(:position, :id) }, dependent: :restrict_with_exception

  scope :kept, -> { where(deleted_at: nil) }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :body, length: { maximum: MAX_BODY_LENGTH }, allow_nil: true
  validate :sender_participates_in_match
  validate :conversation_matches_brand
  validate :body_or_attachment_present, on: :create
  validate :reply_to_message_is_same_conversation

  before_validation :ensure_public_id, on: :create

  def kept?
    deleted_at.nil?
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def conversation_matches_brand
    return if conversation.blank? || conversation.brand_id == brand_id

    errors.add(:conversation, "must belong to the same brand")
  end

  def sender_participates_in_match
    return if conversation.blank? || sender_profile_id.blank?
    return if [ conversation.match.profile_a_id, conversation.match.profile_b_id ].include?(sender_profile_id)

    errors.add(:sender_profile, "must participate in the conversation match")
  end

  # A message must carry text, an attachment, or both — never neither. Checked
  # against `message_attachments.size` (in-memory association, including
  # not-yet-persisted `build`s from Messaging::SendMessage's single transaction)
  # rather than a query, so this works before the attachments themselves have
  # been saved.
  def body_or_attachment_present
    return if body.present? || message_attachments.size.positive?

    errors.add(:base, "message must have a body or at least one attachment")
  end

  def reply_to_message_is_same_conversation
    return if reply_to_message.blank?
    return if reply_to_message.conversation_id == conversation_id

    errors.add(:reply_to_message, "must belong to the same conversation")
  end
end
