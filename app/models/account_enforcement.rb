class AccountEnforcement < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership
  belongs_to :profile, optional: true
  belongs_to :admin_user
  belongs_to :report, optional: true
  belongs_to :reverted_by, class_name: "AdminUser",
    foreign_key: :reverted_by_admin_user_id, optional: true

  # Not yet reversed. At most one may exist per (brand, user) — DB-enforced.
  scope :active, -> { where(reverted_at: nil) }

  validates :reason, length: { maximum: 500 }, allow_blank: true
  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { active } }, if: -> { reverted_at.nil? }
  validate :consistent_brand

  def reverted?
    reverted_at.present?
  end

  private

  def consistent_brand
    if brand_membership.present? && brand_membership.brand_id != brand_id
      errors.add(:brand_membership, "must belong to the same brand")
    end
    return if profile.blank? || profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same brand")
  end
end
