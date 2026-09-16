class Date9jaHistoryRecord < ApplicationRecord
  belongs_to :brand
  belongs_to :user, optional: true
  belongs_to :profile, optional: true

  validates :source_entity, :source_id, :record_type, presence: true
  validates :source_id, uniqueness: { scope: [ :brand_id, :source_entity ] }
end
