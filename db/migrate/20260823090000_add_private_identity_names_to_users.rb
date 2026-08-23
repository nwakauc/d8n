class AddPrivateIdentityNamesToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :first_name, limit: 100
      t.string :last_name, limit: 100
    end
  end
end
