class Current < ActiveSupport::CurrentAttributes
  attribute :brand, :user, :session, :admin_user, :admin_context, :permissions, :locale, :features, :platform_contract,
    :authentication_source, :authentication_error
end
