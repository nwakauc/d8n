class AddKindAndNoteToAccountEnforcements < ActiveRecord::Migration[8.0]
  def change
    add_column :account_enforcements, :kind, :integer, null: false, default: 0
    add_column :account_enforcements, :note, :text
    add_index :account_enforcements, :kind
  end
end
