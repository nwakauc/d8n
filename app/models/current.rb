class Current < ActiveSupport::CurrentAttributes
  attribute :brand, :user, :session, :admin_user, :permissions, :locale, :features
end
