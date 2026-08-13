require "sequel/core"

Rodauth::Rails.configure do |config|
  config.middleware = false
  config.tilt = false
end

# Password routes and sessions remain D8N-owned. This internal Rodauth
# configuration provides mature password requirements, hashing, and verification
# without mounting a parallel account or session system.
D8nPasswordRodauth = Rodauth::Rails.lib(render: false) do
  enable :login, :change_password

  db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)
  accounts_table :credentials
  login_column :id
  password_hash_table :credential_password_hashes
  password_hash_id_column :credential_id
  convert_token_id_to_integer? true
  use_database_authentication_functions? false

  password_minimum_length 6
  password_maximum_bytes 72
end
