class VerificationAssertion < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :profile, optional: true
  validates :source_type, :source_id, :check_type, :status, presence: true
  validates :source_id, uniqueness: { scope: [ :brand_id, :source_type ] }
end
