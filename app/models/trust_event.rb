# An append-only, brand-scoped, idempotent positive trust award (ADR 0025).
# Never mutated after creation — Trust::Ledger derives the current score by
# summing these rows (plus TrustAdjustment) fresh on every read.
class TrustEvent < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :profile, optional: true

  validates :event_type, :idempotency_key, :occurred_at, presence: true
  validates :points, numericality: { greater_than: 0 }
  validates :idempotency_key, uniqueness: { scope: :brand_id }
end
