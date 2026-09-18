class MessageRead < ApplicationRecord
  belongs_to :brand
  belongs_to :message
  belongs_to :profile
end
