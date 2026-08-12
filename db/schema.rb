# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_12_171633) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_assignments", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.bigint "brand_id", null: false
    t.bigint "admin_role_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_role_id"], name: "index_admin_assignments_on_admin_role_id"
    t.index ["admin_user_id", "brand_id", "admin_role_id"], name: "index_admin_assignments_on_active_role_scope", unique: true, where: "(deleted_at IS NULL)"
    t.index ["admin_user_id"], name: "index_admin_assignments_on_admin_user_id"
    t.index ["brand_id"], name: "index_admin_assignments_on_brand_id"
  end

  create_table "admin_roles", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_admin_roles_on_name", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "admin_users", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "auth_attempts", force: :cascade do |t|
    t.bigint "brand_id"
    t.bigint "user_id"
    t.bigint "identity_identifier_id"
    t.bigint "credential_id"
    t.integer "kind", null: false
    t.integer "result", null: false
    t.string "identifier", null: false
    t.string "ip_address"
    t.text "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "identifier", "created_at"], name: "index_auth_attempts_on_brand_id_and_identifier_and_created_at"
    t.index ["brand_id"], name: "index_auth_attempts_on_brand_id"
    t.index ["credential_id"], name: "index_auth_attempts_on_credential_id"
    t.index ["identity_identifier_id"], name: "index_auth_attempts_on_identity_identifier_id"
    t.index ["ip_address", "created_at"], name: "index_auth_attempts_on_ip_address_and_created_at"
    t.index ["user_id"], name: "index_auth_attempts_on_user_id"
  end

  create_table "brand_domains", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.string "host", null: false
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_brand_domains_on_brand_id"
    t.index ["host"], name: "index_brand_domains_on_host", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "brand_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "brand_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_brand_memberships_on_brand_id"
    t.index ["user_id", "brand_id"], name: "index_brand_memberships_on_user_id_and_brand_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_brand_memberships_on_user_id"
  end

  create_table "brands", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.string "owner_type", default: "D8n", null: false
    t.bigint "owner_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_brands_on_owner_type_and_owner_id"
    t.index ["slug"], name: "index_brands_on_slug", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "credentials", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "identity_identifier_id", null: false
    t.integer "kind", null: false
    t.integer "status", default: 0, null: false
    t.datetime "verified_at"
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_identifier_id"], name: "index_credentials_on_identity_identifier_id"
    t.index ["user_id", "kind", "identity_identifier_id"], name: "index_credentials_on_active_user_kind_identifier", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "identity_identifiers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "kind", null: false
    t.string "normalized_value", null: false
    t.datetime "verified_at"
    t.datetime "last_seen_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "normalized_value"], name: "index_identity_identifiers_on_kind_and_normalized_value", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_identity_identifiers_on_user_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "user_id"
    t.integer "channel", null: false
    t.string "provider", null: false
    t.string "recipient", null: false
    t.integer "status", default: 0, null: false
    t.string "external_id"
    t.string "error_code"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "failed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "channel", "status", "created_at"], name: "idx_on_brand_id_channel_status_created_at_a9a03f5e6e"
    t.index ["brand_id"], name: "index_notification_deliveries_on_brand_id"
    t.index ["provider", "external_id"], name: "index_notification_deliveries_on_provider_and_external_id"
    t.index ["recipient"], name: "index_notification_deliveries_on_recipient"
    t.index ["user_id"], name: "index_notification_deliveries_on_user_id"
  end

  create_table "otp_challenges", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "identity_identifier_id"
    t.integer "kind", null: false
    t.string "identifier", null: false
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.integer "attempt_count", default: 0, null: false
    t.string "ip_address"
    t.text "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "identifier", "kind", "created_at"], name: "idx_on_brand_id_identifier_kind_created_at_7a5f2a0ce9"
    t.index ["brand_id", "identifier", "kind"], name: "index_otp_challenges_on_active_lookup", where: "(consumed_at IS NULL)"
    t.index ["brand_id"], name: "index_otp_challenges_on_brand_id"
    t.index ["identity_identifier_id"], name: "index_otp_challenges_on_identity_identifier_id"
  end

  create_table "profile_photos", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.bigint "user_id", null: false
    t.bigint "brand_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "visibility", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "status", "created_at"], name: "index_profile_photos_on_brand_id_and_status_and_created_at"
    t.index ["brand_id", "user_id", "deleted_at"], name: "index_profile_photos_on_brand_id_and_user_id_and_deleted_at"
    t.index ["brand_id"], name: "index_profile_photos_on_brand_id"
    t.index ["profile_id", "position"], name: "index_profile_photos_on_profile_id_and_position", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_photos_on_profile_id"
    t.index ["user_id"], name: "index_profile_photos_on_user_id"
  end

  create_table "profile_preferences", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.bigint "user_id", null: false
    t.bigint "brand_id", null: false
    t.integer "min_age"
    t.integer "max_age"
    t.jsonb "interested_in", default: [], null: false
    t.integer "max_distance_km"
    t.string "country"
    t.string "relationship_intent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "min_age", "max_age"], name: "index_profile_preferences_on_brand_id_and_min_age_and_max_age"
    t.index ["brand_id"], name: "index_profile_preferences_on_brand_id"
    t.index ["deleted_at"], name: "index_profile_preferences_on_deleted_at"
    t.index ["profile_id"], name: "index_profile_preferences_on_active_profile_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_preferences_on_profile_id"
    t.index ["user_id", "brand_id"], name: "index_profile_preferences_on_active_user_brand", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_profile_preferences_on_user_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.string "display_name"
    t.text "bio"
    t.date "birthdate"
    t.string "gender"
    t.integer "status", default: 0, null: false
    t.integer "visibility", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "status", "visibility", "created_at"], name: "idx_on_brand_id_status_visibility_created_at_3574045134"
    t.index ["brand_id"], name: "index_profiles_on_brand_id"
    t.index ["brand_membership_id"], name: "index_profiles_on_brand_membership_id"
    t.index ["deleted_at"], name: "index_profiles_on_deleted_at"
    t.index ["user_id", "brand_id"], name: "index_profiles_on_user_id_and_brand_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_profiles_on_user_id"
  end

  create_table "security_events", force: :cascade do |t|
    t.bigint "brand_id"
    t.bigint "user_id"
    t.string "event_type", null: false
    t.integer "severity", default: 0, null: false
    t.string "ip_address"
    t.text "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "event_type", "created_at"], name: "idx_on_brand_id_event_type_created_at_eb4d608a37"
    t.index ["brand_id"], name: "index_security_events_on_brand_id"
    t.index ["user_id", "event_type", "created_at"], name: "index_security_events_on_user_id_and_event_type_and_created_at"
    t.index ["user_id"], name: "index_security_events_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "brand_id", null: false
    t.string "token_digest", null: false
    t.string "device_name"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "last_used_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "user_id", "revoked_at"], name: "index_sessions_on_brand_id_and_user_id_and_revoked_at"
    t.index ["brand_id"], name: "index_sessions_on_brand_id"
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_assignments", "admin_roles"
  add_foreign_key "admin_assignments", "admin_users"
  add_foreign_key "admin_assignments", "brands"
  add_foreign_key "auth_attempts", "brands"
  add_foreign_key "auth_attempts", "credentials"
  add_foreign_key "auth_attempts", "identity_identifiers"
  add_foreign_key "auth_attempts", "users"
  add_foreign_key "brand_domains", "brands"
  add_foreign_key "brand_memberships", "brands"
  add_foreign_key "brand_memberships", "users"
  add_foreign_key "credentials", "identity_identifiers"
  add_foreign_key "credentials", "users"
  add_foreign_key "identity_identifiers", "users"
  add_foreign_key "notification_deliveries", "brands"
  add_foreign_key "notification_deliveries", "users"
  add_foreign_key "otp_challenges", "brands"
  add_foreign_key "otp_challenges", "identity_identifiers"
  add_foreign_key "profile_photos", "brands"
  add_foreign_key "profile_photos", "profiles"
  add_foreign_key "profile_photos", "users"
  add_foreign_key "profile_preferences", "brands"
  add_foreign_key "profile_preferences", "profiles"
  add_foreign_key "profile_preferences", "users"
  add_foreign_key "profiles", "brand_memberships"
  add_foreign_key "profiles", "brands"
  add_foreign_key "profiles", "users"
  add_foreign_key "security_events", "brands"
  add_foreign_key "security_events", "users"
  add_foreign_key "sessions", "brands"
  add_foreign_key "sessions", "users"
end
