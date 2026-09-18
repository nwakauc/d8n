class CreateMessageReads < ActiveRecord::Migration[8.1]
  def change
    create_table :message_reads do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :message, null: false
      t.references :profile, null: false
      t.datetime :read_at, null: false
    end
    add_index :message_reads, [ :profile_id, :message_id ], unique: true
    add_foreign_key :message_reads, :messages, column: [ :message_id, :brand_id ],
      primary_key: [ :id, :brand_id ]
    add_foreign_key :message_reads, :profiles, column: [ :profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ]
  end
end
