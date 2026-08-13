class AddCredentialToSessions < ActiveRecord::Migration[8.0]
  def change
    add_reference :sessions, :credential, null: true, foreign_key: true
  end
end
