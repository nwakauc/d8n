class CreateAnalyticsEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_events do |t|
      t.uuid :event_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.references :brand, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :profile, foreign_key: true
      t.references :session, foreign_key: true
      t.jsonb :properties, null: false, default: {}
      t.string :idempotency_key, null: false
      t.timestamps
    end

    add_index :analytics_events, :event_id, unique: true
    add_index :analytics_events, :idempotency_key, unique: true
    add_index :analytics_events, [ :brand_id, :event_type, :occurred_at ],
      name: "idx_analytics_events_brand_type_occurred"
    add_index :analytics_events, [ :brand_id, :user_id, :occurred_at ],
      name: "idx_analytics_events_brand_user_occurred"
  end
end
