class AiUsageEvent < ApplicationRecord
  belongs_to :brand
  belongs_to :brand_membership
  belongs_to :ai_conversation

  enum :status, { completed: 0, unavailable: 1 }, prefix: true

  validates :provider, :model, :request_key, presence: true
  validates :request_key, uniqueness: true
  validate :records_share_brand_and_membership

  private

  def records_share_brand_and_membership
    return if ai_conversation.blank?
    return if ai_conversation.brand_id == brand_id && ai_conversation.brand_membership_id == brand_membership_id

    errors.add(:ai_conversation, "must belong to the same brand membership")
  end
end
