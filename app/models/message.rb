class Message < ApplicationRecord
  # Beta chat is plain text with a bounded length. The limit is generous enough
  # for real conversation but small enough to blunt payload abuse; it is measured
  # in Unicode codepoints after NFC normalization (see Messaging::SendMessage).
  MAX_BODY_LENGTH = 2_000

  belongs_to :brand
  belongs_to :conversation
  belongs_to :sender_profile, class_name: "Profile"

  scope :kept, -> { where(deleted_at: nil) }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validate :sender_participates_in_match
  validate :conversation_matches_brand

  before_validation :ensure_public_id, on: :create

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
end
