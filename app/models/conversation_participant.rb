class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  scope :kept, -> { where(deleted_at: nil) }

  validates :profile_id, uniqueness: { scope: :conversation_id }
  validate :conversation_matches_brand
  validate :profile_matches_scope
  validate :profile_belongs_to_match

  private

  def conversation_matches_brand
    return if conversation.blank? || conversation.brand_id == brand_id

    errors.add(:conversation, "must belong to the same brand")
  end

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
  end

  def profile_belongs_to_match
    return if conversation.blank? || profile.blank?
    return if [ conversation.match.profile_a_id, conversation.match.profile_b_id ].include?(profile_id)

    errors.add(:profile, "must participate in the conversation match")
  end
end
