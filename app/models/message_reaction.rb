# A single emoji reaction a conversation participant placed on a message. Beta
# chat parity with Date9ja `message_reactions`; member-visible in the transcript.
class MessageReaction < ApplicationRecord
  MAX_EMOJI_LENGTH = 16

  belongs_to :brand
  belongs_to :message
  belongs_to :reactor_profile, class_name: "Profile"

  scope :kept, -> { where(deleted_at: nil) }

  validates :emoji, presence: true, length: { maximum: MAX_EMOJI_LENGTH }
  validates :reactor_profile_id, uniqueness: { scope: [ :message_id, :emoji ] }
  validate :message_matches_brand
  validate :reactor_participates_in_conversation

  def kept?
    deleted_at.nil?
  end

  private

  def message_matches_brand
    return if message.blank? || message.brand_id == brand_id

    errors.add(:message, "must belong to the same brand")
  end

  def reactor_participates_in_conversation
    return if message.blank? || reactor_profile_id.blank?

    match = message.conversation.match
    return if [ match.profile_a_id, match.profile_b_id ].include?(reactor_profile_id)

    errors.add(:reactor_profile, "must participate in the conversation")
  end
end
