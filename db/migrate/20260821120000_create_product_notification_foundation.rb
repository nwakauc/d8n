class CreateProductNotificationFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_events do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :idempotency_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :processed_at
      t.integer :processing_attempts, null: false, default: 0
      t.string :last_error_code

      t.timestamps
    end

    add_index :notification_events, :idempotency_key, unique: true
    add_index :notification_events, [ :brand_id, :event_type, :created_at ],
      name: "idx_notification_events_brand_type_created"
    add_foreign_key :notification_events, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_notification_events_membership_owner"

    create_table :notifications do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.references :notification_event, null: false, foreign_key: true, index: { unique: true }
      t.string :notification_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :read_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :notifications, :public_id, unique: true
    add_index :notifications, [ :brand_id, :user_id, :created_at, :id ],
      name: "idx_notifications_inbox"
    add_index :notifications, [ :brand_id, :user_id, :created_at ],
      where: "read_at IS NULL AND deleted_at IS NULL",
      name: "idx_notifications_unread"
    add_index :notifications, [ :id, :brand_id, :user_id ], unique: true,
      name: "idx_notifications_tenant_owner"
    add_foreign_key :notifications, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_notifications_membership_owner"

    create_table :notification_preferences do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.boolean :product_email_enabled, null: false, default: true
      t.boolean :push_enabled, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :notification_preferences, [ :brand_membership_id ], unique: true,
      where: "deleted_at IS NULL", name: "idx_notification_preferences_active_membership"
    add_foreign_key :notification_preferences, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_notification_preferences_membership_owner"

    create_table :device_registrations do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.integer :platform, null: false
      t.text :token, null: false
      t.string :token_digest, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :device_registrations, :public_id, unique: true
    add_index :device_registrations, [ :brand_id, :token_digest ], unique: true,
      where: "revoked_at IS NULL AND deleted_at IS NULL",
      name: "idx_device_registrations_active_token"
    add_index :device_registrations, [ :brand_id, :user_id, :enabled, :last_seen_at ],
      name: "idx_device_registrations_delivery"
    add_foreign_key :device_registrations, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_device_registrations_membership_owner"

    change_table :notification_deliveries, bulk: true do |t|
      t.references :notification, null: true, foreign_key: true
      t.references :device_registration, null: true, foreign_key: true
      t.string :idempotency_key
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_attempted_at
    end

    add_index :notification_deliveries, :idempotency_key, unique: true,
      where: "idempotency_key IS NOT NULL"
    add_index :notification_deliveries, [ :notification_id, :channel ], unique: true,
      where: "notification_id IS NOT NULL AND device_registration_id IS NULL",
      name: "idx_notification_deliveries_one_channel"
    add_index :notification_deliveries, [ :notification_id, :channel, :device_registration_id ], unique: true,
      where: "notification_id IS NOT NULL AND device_registration_id IS NOT NULL",
      name: "idx_notification_deliveries_one_device_channel"
    add_foreign_key :notification_deliveries, :notifications,
      column: [ :notification_id, :brand_id, :user_id ],
      primary_key: [ :id, :brand_id, :user_id ],
      name: "fk_notification_deliveries_notification_owner"
  end
end
