class CreateNotificationDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_deliveries do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.integer :channel, null: false
      t.string :provider, null: false
      t.string :recipient, null: false
      t.integer :status, null: false, default: 0
      t.string :external_id
      t.string :error_code
      t.text :error_message
      t.datetime :sent_at
      t.datetime :failed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :notification_deliveries, [ :brand_id, :channel, :status, :created_at ]
    add_index :notification_deliveries, [ :provider, :external_id ]
    add_index :notification_deliveries, :recipient
  end
end
