class AddHookusProfileDetails < ActiveRecord::Migration[8.0]
  def change
    change_table :profiles, bulk: true do |t|
      t.string :country_code, limit: 2
      t.string :city, limit: 120
      t.string :occupation, limit: 120
      t.integer :height_cm
      t.string :body_type, limit: 80
      t.jsonb :languages_spoken, null: false, default: []
      t.string :smoking, limit: 32
      t.string :drinking, limit: 32
      t.string :fitness, limit: 32
    end

    add_index :profiles, [ :brand_id, :country_code, :city ]
  end
end
