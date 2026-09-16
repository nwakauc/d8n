class AddDate9jaOnboardingFields < ActiveRecord::Migration[8.1]
  def change
    change_table :profiles, bulk: true do |t|
      t.boolean :is_nigerian
      t.string :state_of_origin, limit: 80
      t.string :nationality, limit: 2
      t.text :ideal_partner_description
      t.boolean :willing_to_relocate
      t.string :relocation_preferences, array: true, default: [], null: false
    end
  end
end
