class Current < ActiveSupport::CurrentAttributes
  attribute :brand, :user, :session, :admin_user, :permissions, :locale, :features, :platform_contract,
    :authentication_source, :authentication_error
end
