class AddPrivateAssuranceMetadataToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :metadata, :jsonb, null: false, default: {}
  end
end
