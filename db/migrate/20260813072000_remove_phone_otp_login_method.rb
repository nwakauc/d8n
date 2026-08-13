class RemovePhoneOtpLoginMethod < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE brands
      SET auth_methods = auth_methods - 'phone_otp', updated_at = CURRENT_TIMESTAMP
      WHERE auth_methods ? 'phone_otp'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "phone_otp was a login method; identifier verification is now session-authenticated"
  end
end
