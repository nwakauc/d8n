class NotificationPreference < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership

  scope :kept, -> { where(deleted_at: nil) }

  validates :brand_membership_id, uniqueness: { conditions: -> { kept } }
  validate :membership_matches_recipient

  # Authentication and security-critical delivery are deliberately not generic
  # opt-outs. This V1 record controls only ordinary product email and push.
  def allows?(category)
    case category.to_sym
    when :product_email then product_email_enabled?
    when :push then push_enabled?
    when :security_email, :transactional_email then true
    else false
    end
  end

  private

  def membership_matches_recipient
    return if brand_membership.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id

    errors.add(:brand_membership, "must belong to the preference brand and user")
  end
end
