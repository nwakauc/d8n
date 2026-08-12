class CreateSecurityEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :security_events do |t|
      t.references :brand, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.integer :severity, null: false, default: 0
      t.string :ip_address
      t.text :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :security_events, [ :brand_id, :event_type, :created_at ]
    add_index :security_events, [ :user_id, :event_type, :created_at ]
  end
end
