class Current < ActiveSupport::CurrentAttributes
  attribute :brand, :user, :admin_user, :permissions, :locale, :features
end
