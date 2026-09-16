class CreateDate9jaHistoryRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :date9ja_history_records do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :profile, null: true, foreign_key: true
      t.string :source_entity, null: false
      t.string :source_id, null: false
      t.string :record_type, null: false
      t.string :status
      t.datetime :occurred_at
      t.datetime :redacted_at
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :date9ja_history_records, [ :brand_id, :source_entity, :source_id ], unique: true,
      name: "idx_date9ja_history_records_source"
    add_index :date9ja_history_records, [ :brand_id, :record_type, :occurred_at ],
      name: "idx_date9ja_history_records_timeline"
  end
end
