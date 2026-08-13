class AddAuthMethodsToBrands < ActiveRecord::Migration[8.0]
  def up
    add_column :brands, :auth_methods, :jsonb, null: false, default: []

    # Configure only the explicitly approved initial products. Newly provisioned
    # brands remain deny-by-default.
    execute <<~SQL.squish
      UPDATE brands
      SET auth_methods = '["phone_password", "email_password"]'::jsonb
      WHERE slug IN ('hookus', 'date9ja')
    SQL
  end

  def down
    remove_column :brands, :auth_methods
  end
end
