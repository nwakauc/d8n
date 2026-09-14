class CreateTrustLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :trust_events do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :profile, null: true, foreign_key: true
      t.string :event_type, null: false
      t.integer :points, null: false
      # Informational: the legacy polymorphic source of the award (e.g. a
      # specific photo/verification row), not a D8N association.
      t.string :source_type
      t.string :source_id
      t.string :idempotency_key, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :trust_events, [ :brand_id, :idempotency_key ], unique: true, name: "idx_trust_events_idempotency"
    add_index :trust_events, [ :brand_id, :user_id ], name: "idx_trust_events_lookup"

    create_table :trust_adjustments do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :points, null: false
      t.string :reason_code, null: false
      t.string :appeal_status, null: false, default: "not_requested"
      # Live, D8N-applied adjustments reference a real admin; migrated
      # historical rows have no such account and keep the legacy actor id in
      # `metadata` instead.
      t.references :actor_admin_user, null: true, foreign_key: { to_table: :admin_users }
      t.references :resolved_by_admin_user, null: true, foreign_key: { to_table: :admin_users }
      t.datetime :resolved_at
      t.string :idempotency_key, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :trust_adjustments, [ :brand_id, :idempotency_key ], unique: true, name: "idx_trust_adjustments_idempotency"
    add_index :trust_adjustments, [ :brand_id, :user_id ], name: "idx_trust_adjustments_lookup"
  end
end
