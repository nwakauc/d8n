# An append-only, brand-scoped, idempotent moderator-applied negative trust
# entry, with an appeal lifecycle (ADR 0025). Never mutated after creation
# except to record an appeal decision — an overturned adjustment stays in the
# ledger (audit integrity); Trust::Ledger's rebuild reflects it by summing
# only rows whose points still apply (see `#counts_toward_score?`).
class TrustAdjustment < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :actor_admin_user, class_name: "AdminUser", optional: true
  belongs_to :resolved_by_admin_user, class_name: "AdminUser", optional: true

  enum :appeal_status, { not_requested: "not_requested", pending: "pending", upheld: "upheld", overturned: "overturned" },
    validate: true

  validates :reason_code, :idempotency_key, :occurred_at, presence: true
  validates :points, numericality: { less_than: 0 }
  validates :idempotency_key, uniqueness: { scope: :brand_id }

  # An overturned adjustment is preserved for audit but no longer reduces the
  # derived score — Trust::Ledger sums only rows where this is true.
  def counts_toward_score?
    !overturned?
  end
end
