class VerificationAssertion < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :profile, optional: true

  # Raw member-submitted selfie/liveness-video/government-ID evidence
  # (Identity::RealmeSubmission). Admin-review-only — never delivered to any
  # other member. Absent on rows created by the Date9ja historical importer,
  # which carries only jsonb `evidence` metadata for its legacy records.
  has_one_attached :evidence

  validates :source_type, :source_id, :check_type, :status, presence: true
  validates :source_id, uniqueness: { scope: [ :brand_id, :source_type ] }
end
