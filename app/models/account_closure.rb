class AccountClosure < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership
  belongs_to :profile, optional: true

  # Async physical media purge lifecycle, tracked so a failed purge is visible to
  # operators (never silently marked done while R2 objects remain).
  enum :media_purge_state, { pending: 0, completed: 1, failed: 2 }, prefix: :media_purge

  # One closure per membership instance — DB-enforced, and the basis for idempotency.
  validates :brand_membership_id, uniqueness: true
end
