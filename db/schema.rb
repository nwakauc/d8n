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

ActiveRecord::Schema[8.1].define(version: 2026_08_23_091000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_closures", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.integer "media_purge_state", default: 0, null: false
    t.datetime "media_purged_at"
    t.bigint "profile_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id"], name: "index_account_closures_on_brand_id"
    t.index ["brand_membership_id"], name: "index_account_closures_on_brand_membership_id", unique: true
    t.index ["profile_id"], name: "index_account_closures_on_profile_id"
    t.index ["user_id"], name: "index_account_closures_on_user_id"
  end

  create_table "account_enforcements", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.bigint "profile_id"
    t.text "reason"
    t.bigint "report_id"
    t.datetime "reverted_at"
    t.bigint "reverted_by_admin_user_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["admin_user_id"], name: "index_account_enforcements_on_admin_user_id"
    t.index ["brand_id", "user_id"], name: "idx_account_enforcements_active_unique", unique: true, where: "(reverted_at IS NULL)"
    t.index ["brand_id"], name: "index_account_enforcements_on_brand_id"
    t.index ["brand_membership_id"], name: "index_account_enforcements_on_brand_membership_id"
    t.index ["profile_id"], name: "index_account_enforcements_on_profile_id"
    t.index ["report_id"], name: "index_account_enforcements_on_report_id"
    t.index ["reverted_by_admin_user_id"], name: "index_account_enforcements_on_reverted_by_admin_user_id"
    t.index ["user_id"], name: "index_account_enforcements_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_assignments", force: :cascade do |t|
    t.bigint "admin_role_id", null: false
    t.bigint "admin_user_id", null: false
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["admin_role_id"], name: "index_admin_assignments_on_admin_role_id"
    t.index ["admin_user_id", "brand_id", "admin_role_id"], name: "index_admin_assignments_on_active_role_scope", unique: true, where: "(deleted_at IS NULL)"
    t.index ["admin_user_id"], name: "index_admin_assignments_on_admin_user_id"
    t.index ["brand_id"], name: "index_admin_assignments_on_brand_id"
  end

  create_table "admin_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_admin_roles_on_name", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_admin_users_on_user_id", unique: true
  end

  create_table "auth_attempts", force: :cascade do |t|
    t.bigint "brand_id"
    t.datetime "created_at", null: false
    t.bigint "credential_id"
    t.string "identifier", null: false
    t.bigint "identity_identifier_id"
    t.string "ip_address"
    t.integer "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "result", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id"
    t.index ["brand_id", "identifier", "created_at"], name: "index_auth_attempts_on_brand_id_and_identifier_and_created_at"
    t.index ["brand_id"], name: "index_auth_attempts_on_brand_id"
    t.index ["credential_id"], name: "index_auth_attempts_on_credential_id"
    t.index ["identity_identifier_id"], name: "index_auth_attempts_on_identity_identifier_id"
    t.index ["ip_address", "created_at"], name: "index_auth_attempts_on_ip_address_and_created_at"
    t.index ["user_id"], name: "index_auth_attempts_on_user_id"
  end

  create_table "brand_domains", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "host", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_brand_domains_on_brand_id"
    t.index ["host"], name: "index_brand_domains_on_host", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "brand_memberships", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id"], name: "index_brand_memberships_on_brand_id"
    t.index ["id", "user_id", "brand_id"], name: "idx_memberships_on_id_user_brand", unique: true
    t.index ["user_id", "brand_id"], name: "index_brand_memberships_on_user_id_and_brand_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_brand_memberships_on_user_id"
  end

  create_table "brands", force: :cascade do |t|
    t.jsonb "auth_methods", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "owner_type", default: "D8n", null: false
    t.jsonb "profile_requirements", default: {"collections"=>["photos"], "profile_fields"=>["display_name", "birthdate", "gender"], "preference_fields"=>["min_age", "max_age", "interested_in"]}, null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_brands_on_owner_type_and_owner_id"
    t.index ["slug"], name: "index_brands_on_slug", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "brand_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "last_read_at"
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "profile_id", "conversation_id"], name: "idx_conversation_participants_profile_list"
    t.index ["brand_id"], name: "index_conversation_participants_on_brand_id"
    t.index ["conversation_id", "profile_id"], name: "idx_conversation_participants_unique_profile", unique: true
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["profile_id"], name: "index_conversation_participants_on_profile_id"
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "match_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "created_at", "public_id"], name: "idx_conversations_brand_cursor"
    t.index ["brand_id"], name: "index_conversations_on_brand_id"
    t.index ["id", "brand_id"], name: "idx_conversations_on_id_brand", unique: true
    t.index ["match_id"], name: "index_conversations_on_match_id", unique: true
    t.index ["public_id"], name: "index_conversations_on_public_id", unique: true
  end

  create_table "credential_password_hashes", primary_key: "credential_id", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "credential_kind", default: 0, null: false
    t.datetime "password_changed_at", null: false
    t.string "password_hash", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "credential_kind = 0", name: "chk_password_hash_credential_kind"
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "identity_identifier_id", null: false
    t.integer "kind", null: false
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "verified_at"
    t.index ["id", "kind"], name: "idx_credentials_on_id_kind", unique: true
    t.index ["identity_identifier_id"], name: "index_credentials_on_identity_identifier_id"
    t.index ["user_id", "kind", "identity_identifier_id"], name: "index_credentials_on_active_user_kind_identifier", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "device_registrations", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "enabled", default: true, null: false
    t.datetime "last_seen_at", null: false
    t.integer "platform", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "revoked_at"
    t.text "token", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "token_digest"], name: "idx_device_registrations_active_token", unique: true, where: "((revoked_at IS NULL) AND (deleted_at IS NULL))"
    t.index ["brand_id", "user_id", "enabled", "last_seen_at"], name: "idx_device_registrations_delivery"
    t.index ["brand_id"], name: "index_device_registrations_on_brand_id"
    t.index ["brand_membership_id"], name: "index_device_registrations_on_brand_membership_id"
    t.index ["public_id"], name: "index_device_registrations_on_public_id", unique: true
    t.index ["user_id"], name: "index_device_registrations_on_user_id"
  end

  create_table "find_profile_exposures", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.bigint "candidate_profile_id", null: false
    t.datetime "created_at", null: false
    t.date "exposure_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "viewer_profile_id", null: false
    t.index ["brand_id", "brand_membership_id", "candidate_profile_id", "exposure_date"], name: "idx_find_exposures_unique_member_candidate_day", unique: true
    t.index ["brand_id", "brand_membership_id", "exposure_date"], name: "idx_find_exposures_member_day"
    t.index ["brand_id"], name: "index_find_profile_exposures_on_brand_id"
    t.index ["brand_membership_id"], name: "index_find_profile_exposures_on_brand_membership_id"
    t.index ["candidate_profile_id"], name: "index_find_profile_exposures_on_candidate_profile_id"
    t.index ["user_id"], name: "index_find_profile_exposures_on_user_id"
    t.index ["viewer_profile_id"], name: "index_find_profile_exposures_on_viewer_profile_id"
    t.check_constraint "viewer_profile_id <> candidate_profile_id", name: "chk_find_exposures_not_self"
  end

  create_table "hook_tonight_states", force: :cascade do |t|
    t.datetime "activated_at", null: false
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.datetime "expires_at", null: false
    t.string "intent", default: "open_to_meeting", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "expires_at"], name: "idx_hook_tonight_states_live"
    t.index ["brand_id", "profile_id"], name: "index_hook_tonight_states_on_brand_and_profile", unique: true
    t.index ["brand_id"], name: "index_hook_tonight_states_on_brand_id"
    t.index ["id", "brand_id"], name: "idx_hook_tonight_states_on_id_brand", unique: true
    t.index ["profile_id"], name: "index_hook_tonight_states_on_profile_id"
  end

  create_table "hooks", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "brand_id", null: false
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.datetime "deleted_at"
    t.datetime "expires_at", null: false
    t.text "message", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "recipient_profile_id", null: false
    t.bigint "sender_profile_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "recipient_profile_id", "status", "created_at"], name: "idx_hooks_recipient_inbox"
    t.index ["brand_id", "sender_profile_id", "created_at"], name: "idx_hooks_sender_created"
    t.index ["brand_id", "sender_profile_id", "recipient_profile_id"], name: "idx_hooks_sender_recipient", unique: true
    t.index ["brand_id"], name: "index_hooks_on_brand_id"
    t.index ["conversation_id"], name: "index_hooks_on_conversation_id"
    t.index ["id", "brand_id"], name: "idx_hooks_on_id_brand", unique: true
    t.index ["public_id"], name: "index_hooks_on_public_id", unique: true
    t.index ["recipient_profile_id"], name: "index_hooks_on_recipient_profile_id"
    t.index ["sender_profile_id"], name: "index_hooks_on_sender_profile_id"
    t.check_constraint "sender_profile_id <> recipient_profile_id", name: "chk_hooks_not_self"
  end

  create_table "identity_identifiers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "kind", null: false
    t.datetime "last_seen_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "normalized_value", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "verified_at"
    t.index ["kind", "normalized_value"], name: "index_identity_identifiers_on_kind_and_normalized_value", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_identity_identifiers_on_user_id"
  end

  create_table "likes", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "kind", default: 0, null: false
    t.bigint "liked_profile_id", null: false
    t.bigint "liker_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "liker_profile_id", "liked_profile_id"], name: "idx_likes_active_pair", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_likes_on_brand_id"
    t.index ["liked_profile_id"], name: "index_likes_on_liked_profile_id"
    t.index ["liker_profile_id"], name: "index_likes_on_liker_profile_id"
    t.check_constraint "liker_profile_id <> liked_profile_id", name: "chk_likes_not_self"
  end

  create_table "matches", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "profile_a_id", null: false
    t.bigint "profile_b_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "profile_a_id", "created_at"], name: "index_matches_on_brand_id_and_profile_a_id_and_created_at"
    t.index ["brand_id", "profile_a_id", "profile_b_id"], name: "idx_matches_active_pair", unique: true, where: "((deleted_at IS NULL) AND (status = 0))"
    t.index ["brand_id", "profile_b_id", "created_at"], name: "index_matches_on_brand_id_and_profile_b_id_and_created_at"
    t.index ["brand_id"], name: "index_matches_on_brand_id"
    t.index ["id", "brand_id"], name: "idx_matches_on_id_brand", unique: true
    t.index ["profile_a_id"], name: "index_matches_on_profile_a_id"
    t.index ["profile_b_id"], name: "index_matches_on_profile_b_id"
    t.index ["public_id"], name: "index_matches_on_public_id", unique: true
    t.check_constraint "profile_a_id < profile_b_id", name: "chk_matches_canonical_pair"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "brand_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "sender_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_messages_on_brand_id"
    t.index ["conversation_id", "created_at", "id"], name: "idx_messages_conversation_cursor", where: "(deleted_at IS NULL)"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["id", "brand_id"], name: "idx_messages_on_id_brand", unique: true
    t.index ["public_id"], name: "index_messages_on_public_id", unique: true
    t.index ["sender_profile_id"], name: "index_messages_on_sender_profile_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.bigint "brand_id", null: false
    t.integer "channel", null: false
    t.datetime "created_at", null: false
    t.bigint "device_registration_id"
    t.string "error_code"
    t.text "error_message"
    t.string "external_id"
    t.datetime "failed_at"
    t.string "idempotency_key"
    t.datetime "last_attempted_at"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "notification_id"
    t.string "provider", null: false
    t.string "recipient", null: false
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["brand_id", "channel", "status", "created_at"], name: "idx_on_brand_id_channel_status_created_at_a9a03f5e6e"
    t.index ["brand_id"], name: "index_notification_deliveries_on_brand_id"
    t.index ["device_registration_id"], name: "index_notification_deliveries_on_device_registration_id"
    t.index ["idempotency_key"], name: "index_notification_deliveries_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["notification_id", "channel", "device_registration_id"], name: "idx_notification_deliveries_one_device_channel", unique: true, where: "((notification_id IS NOT NULL) AND (device_registration_id IS NOT NULL))"
    t.index ["notification_id", "channel"], name: "idx_notification_deliveries_one_channel", unique: true, where: "((notification_id IS NOT NULL) AND (device_registration_id IS NULL))"
    t.index ["notification_id"], name: "index_notification_deliveries_on_notification_id"
    t.index ["provider", "external_id"], name: "index_notification_deliveries_on_provider_and_external_id"
    t.index ["recipient"], name: "index_notification_deliveries_on_recipient"
    t.index ["user_id"], name: "index_notification_deliveries_on_user_id"
  end

  create_table "notification_events", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "idempotency_key", null: false
    t.string "last_error_code"
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.integer "processing_attempts", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "event_type", "created_at"], name: "idx_notification_events_brand_type_created"
    t.index ["brand_id"], name: "index_notification_events_on_brand_id"
    t.index ["brand_membership_id"], name: "index_notification_events_on_brand_membership_id"
    t.index ["idempotency_key"], name: "index_notification_events_on_idempotency_key", unique: true
    t.index ["user_id"], name: "index_notification_events_on_user_id"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "product_email_enabled", default: true, null: false
    t.boolean "push_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id"], name: "index_notification_preferences_on_brand_id"
    t.index ["brand_membership_id"], name: "idx_notification_preferences_active_membership", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_membership_id"], name: "index_notification_preferences_on_brand_membership_id"
    t.index ["user_id"], name: "index_notification_preferences_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "notification_event_id", null: false
    t.string "notification_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "user_id", "created_at", "id"], name: "idx_notifications_inbox"
    t.index ["brand_id", "user_id", "created_at"], name: "idx_notifications_unread", where: "((read_at IS NULL) AND (deleted_at IS NULL))"
    t.index ["brand_id"], name: "index_notifications_on_brand_id"
    t.index ["brand_membership_id"], name: "index_notifications_on_brand_membership_id"
    t.index ["id", "brand_id", "user_id"], name: "idx_notifications_tenant_owner", unique: true
    t.index ["notification_event_id"], name: "index_notifications_on_notification_event_id", unique: true
    t.index ["public_id"], name: "index_notifications_on_public_id", unique: true
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "otp_challenges", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.bigint "brand_id", null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.text "delivery_code"
    t.datetime "expires_at", null: false
    t.string "identifier", null: false
    t.bigint "identity_identifier_id"
    t.string "ip_address"
    t.integer "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["brand_id", "identifier", "kind", "created_at"], name: "idx_on_brand_id_identifier_kind_created_at_7a5f2a0ce9"
    t.index ["brand_id", "identifier", "kind"], name: "index_otp_challenges_on_active_lookup", where: "(consumed_at IS NULL)"
    t.index ["brand_id"], name: "index_otp_challenges_on_brand_id"
    t.index ["identity_identifier_id"], name: "index_otp_challenges_on_identity_identifier_id"
  end

  create_table "profile_blocks", force: :cascade do |t|
    t.bigint "blocked_profile_id", null: false
    t.bigint "blocker_profile_id", null: false
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "updated_at", null: false
    t.index ["blocked_profile_id"], name: "index_profile_blocks_on_blocked_profile_id"
    t.index ["blocker_profile_id"], name: "index_profile_blocks_on_blocker_profile_id"
    t.index ["brand_id", "blocked_profile_id"], name: "idx_profile_blocks_active_incoming", where: "(deleted_at IS NULL)"
    t.index ["brand_id", "blocker_profile_id", "blocked_profile_id"], name: "idx_profile_blocks_active_pair", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_id", "blocker_profile_id"], name: "idx_profile_blocks_active_outgoing", where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_profile_blocks_on_brand_id"
    t.check_constraint "blocker_profile_id <> blocked_profile_id", name: "chk_profile_blocks_not_self"
  end

  create_table "profile_locations", force: :cascade do |t|
    t.integer "accuracy_meters", null: false
    t.bigint "brand_id", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.bigint "profile_id", null: false
    t.string "source", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "latitude", "longitude"], name: "idx_profile_locations_active_coordinates", where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_profile_locations_on_brand_id"
    t.index ["profile_id"], name: "idx_profile_locations_active_profile", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_locations_on_profile_id"
    t.index ["user_id"], name: "index_profile_locations_on_user_id"
    t.check_constraint "accuracy_meters >= 0 AND accuracy_meters <= 100000", name: "chk_profile_locations_accuracy"
    t.check_constraint "latitude >= '-90'::integer::numeric AND latitude <= 90::numeric", name: "chk_profile_locations_latitude"
    t.check_constraint "longitude >= '-180'::integer::numeric AND longitude <= 180::numeric", name: "chk_profile_locations_longitude"
    t.check_constraint "source::text = ANY (ARRAY['device'::character varying::text, 'manual'::character varying::text, 'imported'::character varying::text])", name: "chk_profile_locations_source"
  end

  create_table "profile_option_groups", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.integer "cardinality", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "key", limit: 80, null: false
    t.string "label", limit: 120, null: false
    t.integer "max_selections", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["brand_id", "key"], name: "idx_profile_option_groups_active_key", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_profile_option_groups_on_brand_id"
    t.index ["id", "brand_id"], name: "idx_profile_option_groups_id_brand", unique: true
    t.check_constraint "\"position\" >= 0", name: "chk_profile_option_groups_position"
    t.check_constraint "max_selections > 0", name: "chk_profile_option_groups_max_selections"
  end

  create_table "profile_option_selections", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "profile_id", null: false
    t.bigint "profile_option_group_id", null: false
    t.bigint "profile_option_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "profile_option_group_id"], name: "idx_on_brand_id_profile_option_group_id_415cfbaf56"
    t.index ["brand_id"], name: "index_profile_option_selections_on_brand_id"
    t.index ["profile_id", "profile_option_group_id", "profile_option_id"], name: "idx_profile_option_selections_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_option_selections_on_profile_id"
    t.index ["profile_option_group_id"], name: "index_profile_option_selections_on_profile_option_group_id"
    t.index ["profile_option_id"], name: "index_profile_option_selections_on_profile_option_id"
    t.index ["user_id"], name: "index_profile_option_selections_on_user_id"
  end

  create_table "profile_options", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.string "category", limit: 40
    t.string "code", limit: 80, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "label", limit: 120, null: false
    t.integer "position", default: 0, null: false
    t.bigint "profile_option_group_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_profile_options_on_brand_id"
    t.index ["id", "profile_option_group_id", "brand_id"], name: "idx_profile_options_id_group_brand", unique: true
    t.index ["profile_option_group_id", "category"], name: "index_profile_options_on_group_and_category", where: "(category IS NOT NULL)"
    t.index ["profile_option_group_id", "code"], name: "idx_profile_options_active_code", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_option_group_id"], name: "index_profile_options_on_profile_option_group_id"
    t.check_constraint "\"position\" >= 0", name: "chk_profile_options_position"
  end

  create_table "profile_passes", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "passed_profile_id", null: false
    t.bigint "passer_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "passer_profile_id", "passed_profile_id"], name: "idx_profile_passes_active_pair", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_profile_passes_on_brand_id"
    t.index ["passed_profile_id"], name: "index_profile_passes_on_passed_profile_id"
    t.index ["passer_profile_id"], name: "index_profile_passes_on_passer_profile_id"
    t.check_constraint "passer_profile_id <> passed_profile_id", name: "chk_profile_passes_not_self"
  end

  create_table "profile_photos", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "processed_at"
    t.integer "processing_state", default: 0, null: false
    t.bigint "profile_id", null: false
    t.string "public_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["brand_id", "processing_state"], name: "index_profile_photos_on_brand_id_and_processing_state"
    t.index ["brand_id", "status", "created_at"], name: "index_profile_photos_on_brand_id_and_status_and_created_at"
    t.index ["brand_id", "user_id", "deleted_at"], name: "index_profile_photos_on_brand_id_and_user_id_and_deleted_at"
    t.index ["brand_id"], name: "index_profile_photos_on_brand_id"
    t.index ["profile_id", "position"], name: "index_profile_photos_on_profile_id_and_position", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_photos_on_profile_id"
    t.index ["public_id"], name: "index_profile_photos_on_public_id", unique: true
    t.index ["user_id"], name: "index_profile_photos_on_user_id"
  end

  create_table "profile_preferences", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.jsonb "interested_in", default: [], null: false
    t.integer "max_age"
    t.integer "max_distance_km"
    t.jsonb "metadata", default: {}, null: false
    t.integer "min_age"
    t.bigint "profile_id", null: false
    t.string "relationship_intent"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id", "min_age", "max_age"], name: "index_profile_preferences_on_brand_id_and_min_age_and_max_age"
    t.index ["brand_id"], name: "index_profile_preferences_on_brand_id"
    t.index ["deleted_at"], name: "index_profile_preferences_on_deleted_at"
    t.index ["profile_id"], name: "index_profile_preferences_on_active_profile_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_preferences_on_profile_id"
    t.index ["user_id", "brand_id"], name: "index_profile_preferences_on_active_user_brand", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_profile_preferences_on_user_id"
  end

  create_table "profile_prompt_answers", force: :cascade do |t|
    t.text "answer", null: false
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "position", default: 0, null: false
    t.bigint "profile_id", null: false
    t.bigint "profile_prompt_id", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_profile_prompt_answers_on_brand_id"
    t.index ["profile_id", "profile_prompt_id"], name: "idx_profile_prompt_answers_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["profile_id"], name: "index_profile_prompt_answers_on_profile_id"
    t.index ["profile_prompt_id"], name: "index_profile_prompt_answers_on_profile_prompt_id"
    t.check_constraint "\"position\" >= 0", name: "chk_profile_prompt_answers_position"
  end

  create_table "profile_prompts", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.string "category", limit: 40
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "key", limit: 80, null: false
    t.integer "position", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "text", limit: 160, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "key"], name: "idx_profile_prompts_active_key", unique: true, where: "(deleted_at IS NULL)"
    t.index ["brand_id"], name: "index_profile_prompts_on_brand_id"
    t.index ["id", "brand_id"], name: "idx_profile_prompts_on_id_brand", unique: true
    t.check_constraint "\"position\" >= 0", name: "chk_profile_prompts_position"
  end

  create_table "profiles", force: :cascade do |t|
    t.text "bio"
    t.date "birthdate"
    t.string "body_type", limit: 80
    t.bigint "brand_id", null: false
    t.bigint "brand_membership_id", null: false
    t.integer "children_count"
    t.string "city", limit: 120
    t.string "company_name", limit: 120
    t.string "country_code", limit: 2
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_name"
    t.string "drinking", limit: 32
    t.string "fitness", limit: 32
    t.string "gender"
    t.integer "height_cm"
    t.string "job_title", limit: 120
    t.jsonb "languages", default: [], null: false
    t.jsonb "languages_spoken", default: [], null: false
    t.text "looking_for_text"
    t.jsonb "metadata", default: {}, null: false
    t.string "occupation", limit: 120
    t.string "pronouns", limit: 40
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "school_or_institution", limit: 160
    t.string "smoking", limit: 32
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["brand_id", "country_code", "city"], name: "index_profiles_on_brand_id_and_country_code_and_city"
    t.index ["brand_id", "status", "visibility", "created_at"], name: "idx_on_brand_id_status_visibility_created_at_3574045134"
    t.index ["brand_id"], name: "index_profiles_on_brand_id"
    t.index ["brand_membership_id"], name: "index_profiles_on_brand_membership_id"
    t.index ["deleted_at"], name: "index_profiles_on_deleted_at"
    t.index ["id", "brand_id"], name: "idx_profiles_on_id_brand", unique: true
    t.index ["id", "user_id", "brand_id"], name: "idx_profiles_on_id_user_brand", unique: true
    t.index ["public_id"], name: "index_profiles_on_public_id", unique: true
    t.index ["user_id", "brand_id"], name: "index_profiles_on_user_id_and_brand_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_profiles_on_user_id"
    t.check_constraint "children_count IS NULL OR children_count >= 0 AND children_count <= 30", name: "chk_profiles_children_count"
  end

  create_table "rate_limit_counters", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "throttle_key", null: false
    t.datetime "updated_at", null: false
    t.datetime "window_started_at", null: false
    t.index ["expires_at"], name: "idx_rate_limit_counters_expiry"
    t.index ["throttle_key", "window_started_at"], name: "idx_rate_limit_counters_bucket", unique: true
    t.check_constraint "count >= 0", name: "chk_rate_limit_counters_count"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: {}, null: false
    t.text "note"
    t.integer "reason", null: false
    t.bigint "reported_profile_id", null: false
    t.bigint "reporter_profile_id", null: false
    t.text "resolution_note"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_admin_user_id"
    t.integer "status", default: 0, null: false
    t.bigint "target_id"
    t.integer "target_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "reported_profile_id"], name: "index_reports_on_brand_id_and_reported_profile_id"
    t.index ["brand_id", "reporter_profile_id", "reported_profile_id"], name: "idx_reports_open_profile", unique: true, where: "((status = 0) AND (target_id IS NULL))"
    t.index ["brand_id", "status", "created_at"], name: "index_reports_on_brand_id_and_status_and_created_at"
    t.index ["brand_id", "target_type", "created_at"], name: "index_reports_on_brand_id_and_target_type_and_created_at"
    t.index ["brand_id", "target_type", "target_id"], name: "idx_reports_open_target", unique: true, where: "((status = 0) AND (target_id IS NOT NULL))"
    t.index ["brand_id"], name: "index_reports_on_brand_id"
    t.index ["reported_profile_id"], name: "index_reports_on_reported_profile_id"
    t.index ["reporter_profile_id"], name: "index_reports_on_reporter_profile_id"
    t.index ["reviewed_by_admin_user_id"], name: "index_reports_on_reviewed_by_admin_user_id"
    t.check_constraint "reporter_profile_id <> reported_profile_id", name: "chk_reports_not_self"
  end

  create_table "security_events", force: :cascade do |t|
    t.bigint "brand_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.integer "severity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id"
    t.index ["brand_id", "event_type", "created_at"], name: "idx_on_brand_id_event_type_created_at_eb4d608a37"
    t.index ["brand_id"], name: "index_security_events_on_brand_id"
    t.index ["user_id", "event_type", "created_at"], name: "index_security_events_on_user_id_and_event_type_and_created_at"
    t.index ["user_id"], name: "index_security_events_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.bigint "credential_id"
    t.string "device_name"
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_used_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["brand_id", "user_id", "revoked_at"], name: "index_sessions_on_brand_id_and_user_id_and_revoked_at"
    t.index ["brand_id"], name: "index_sessions_on_brand_id"
    t.index ["credential_id"], name: "index_sessions_on_credential_id"
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "first_name", limit: 100
    t.string "last_name", limit: 100
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "account_closures", "brand_memberships"
  add_foreign_key "account_closures", "brands"
  add_foreign_key "account_closures", "profiles"
  add_foreign_key "account_closures", "users"
  add_foreign_key "account_enforcements", "admin_users"
  add_foreign_key "account_enforcements", "admin_users", column: "reverted_by_admin_user_id"
  add_foreign_key "account_enforcements", "brand_memberships"
  add_foreign_key "account_enforcements", "brands"
  add_foreign_key "account_enforcements", "profiles"
  add_foreign_key "account_enforcements", "reports"
  add_foreign_key "account_enforcements", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_assignments", "admin_roles"
  add_foreign_key "admin_assignments", "admin_users"
  add_foreign_key "admin_assignments", "brands"
  add_foreign_key "admin_users", "users"
  add_foreign_key "auth_attempts", "brands"
  add_foreign_key "auth_attempts", "credentials"
  add_foreign_key "auth_attempts", "identity_identifiers"
  add_foreign_key "auth_attempts", "users"
  add_foreign_key "brand_domains", "brands"
  add_foreign_key "brand_memberships", "brands"
  add_foreign_key "brand_memberships", "users"
  add_foreign_key "conversation_participants", "brands"
  add_foreign_key "conversation_participants", "conversations", column: ["conversation_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_conversation_participants_conversation_tenant"
  add_foreign_key "conversation_participants", "profiles", column: ["profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_conversation_participants_profile_tenant"
  add_foreign_key "conversation_participants", "users"
  add_foreign_key "conversations", "brands"
  add_foreign_key "conversations", "matches", column: ["match_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_conversations_match_tenant"
  add_foreign_key "credential_password_hashes", "credentials", column: ["credential_id", "credential_kind"], primary_key: ["id", "kind"], name: "fk_password_hash_credential_kind"
  add_foreign_key "credentials", "identity_identifiers"
  add_foreign_key "credentials", "users"
  add_foreign_key "device_registrations", "brand_memberships"
  add_foreign_key "device_registrations", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_device_registrations_membership_owner"
  add_foreign_key "device_registrations", "brands"
  add_foreign_key "device_registrations", "users"
  add_foreign_key "find_profile_exposures", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_find_exposures_membership_tenant"
  add_foreign_key "find_profile_exposures", "brands"
  add_foreign_key "find_profile_exposures", "profiles", column: ["candidate_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_find_exposures_candidate_tenant"
  add_foreign_key "find_profile_exposures", "profiles", column: ["viewer_profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_find_exposures_viewer_tenant"
  add_foreign_key "find_profile_exposures", "users"
  add_foreign_key "hook_tonight_states", "brands"
  add_foreign_key "hook_tonight_states", "profiles", column: ["profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_hook_tonight_states_profile_tenant"
  add_foreign_key "hooks", "brands"
  add_foreign_key "hooks", "conversations", column: ["conversation_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_hooks_conversation_tenant"
  add_foreign_key "hooks", "profiles", column: ["recipient_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_hooks_recipient_tenant"
  add_foreign_key "hooks", "profiles", column: ["sender_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_hooks_sender_tenant"
  add_foreign_key "identity_identifiers", "users"
  add_foreign_key "likes", "brands"
  add_foreign_key "likes", "profiles", column: ["liked_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_likes_liked_profile_tenant"
  add_foreign_key "likes", "profiles", column: ["liker_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_likes_liker_profile_tenant"
  add_foreign_key "matches", "brands"
  add_foreign_key "matches", "profiles", column: ["profile_a_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_matches_profile_a_tenant"
  add_foreign_key "matches", "profiles", column: ["profile_b_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_matches_profile_b_tenant"
  add_foreign_key "messages", "brands"
  add_foreign_key "messages", "conversations", column: ["conversation_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_messages_conversation_tenant"
  add_foreign_key "messages", "profiles", column: ["sender_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_messages_sender_tenant"
  add_foreign_key "notification_deliveries", "brands"
  add_foreign_key "notification_deliveries", "device_registrations"
  add_foreign_key "notification_deliveries", "notifications"
  add_foreign_key "notification_deliveries", "notifications", column: ["notification_id", "brand_id", "user_id"], primary_key: ["id", "brand_id", "user_id"], name: "fk_notification_deliveries_notification_owner"
  add_foreign_key "notification_deliveries", "users"
  add_foreign_key "notification_events", "brand_memberships"
  add_foreign_key "notification_events", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_notification_events_membership_owner"
  add_foreign_key "notification_events", "brands"
  add_foreign_key "notification_events", "users"
  add_foreign_key "notification_preferences", "brand_memberships"
  add_foreign_key "notification_preferences", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_notification_preferences_membership_owner"
  add_foreign_key "notification_preferences", "brands"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "notifications", "brand_memberships"
  add_foreign_key "notifications", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_notifications_membership_owner"
  add_foreign_key "notifications", "brands"
  add_foreign_key "notifications", "notification_events"
  add_foreign_key "notifications", "users"
  add_foreign_key "otp_challenges", "brands"
  add_foreign_key "otp_challenges", "identity_identifiers"
  add_foreign_key "profile_blocks", "brands"
  add_foreign_key "profile_blocks", "profiles", column: ["blocked_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_blocks_blocked_tenant"
  add_foreign_key "profile_blocks", "profiles", column: ["blocker_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_blocks_blocker_tenant"
  add_foreign_key "profile_locations", "brands"
  add_foreign_key "profile_locations", "profiles"
  add_foreign_key "profile_locations", "profiles", column: ["profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_profile_locations_profile_tenant"
  add_foreign_key "profile_locations", "users"
  add_foreign_key "profile_option_groups", "brands"
  add_foreign_key "profile_option_selections", "brands"
  add_foreign_key "profile_option_selections", "profile_option_groups"
  add_foreign_key "profile_option_selections", "profile_option_groups", column: ["profile_option_group_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_option_selections_group_tenant"
  add_foreign_key "profile_option_selections", "profile_options"
  add_foreign_key "profile_option_selections", "profile_options", column: ["profile_option_id", "profile_option_group_id", "brand_id"], primary_key: ["id", "profile_option_group_id", "brand_id"], name: "fk_option_selections_option_tenant"
  add_foreign_key "profile_option_selections", "profiles"
  add_foreign_key "profile_option_selections", "profiles", column: ["profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_option_selections_profile_tenant"
  add_foreign_key "profile_option_selections", "users"
  add_foreign_key "profile_options", "brands"
  add_foreign_key "profile_options", "profile_option_groups"
  add_foreign_key "profile_options", "profile_option_groups", column: ["profile_option_group_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_options_group_tenant"
  add_foreign_key "profile_passes", "brands"
  add_foreign_key "profile_passes", "profiles", column: ["passed_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_passes_passed_tenant"
  add_foreign_key "profile_passes", "profiles", column: ["passer_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_passes_passer_tenant"
  add_foreign_key "profile_photos", "brands"
  add_foreign_key "profile_photos", "profiles"
  add_foreign_key "profile_photos", "profiles", column: ["profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_photos_profile_tenant"
  add_foreign_key "profile_photos", "users"
  add_foreign_key "profile_preferences", "brands"
  add_foreign_key "profile_preferences", "profiles"
  add_foreign_key "profile_preferences", "profiles", column: ["profile_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_preferences_profile_tenant"
  add_foreign_key "profile_preferences", "users"
  add_foreign_key "profile_prompt_answers", "brands"
  add_foreign_key "profile_prompt_answers", "profile_prompts", column: ["profile_prompt_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_prompt_answers_prompt_tenant"
  add_foreign_key "profile_prompt_answers", "profiles", column: ["profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_profile_prompt_answers_profile_tenant"
  add_foreign_key "profile_prompts", "brands"
  add_foreign_key "profiles", "brand_memberships"
  add_foreign_key "profiles", "brand_memberships", column: ["brand_membership_id", "user_id", "brand_id"], primary_key: ["id", "user_id", "brand_id"], name: "fk_profiles_membership_tenant"
  add_foreign_key "profiles", "brands"
  add_foreign_key "profiles", "users"
  add_foreign_key "reports", "admin_users", column: "reviewed_by_admin_user_id"
  add_foreign_key "reports", "brands"
  add_foreign_key "reports", "profiles", column: ["reported_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_reports_reported_tenant"
  add_foreign_key "reports", "profiles", column: ["reporter_profile_id", "brand_id"], primary_key: ["id", "brand_id"], name: "fk_reports_reporter_tenant"
  add_foreign_key "security_events", "brands"
  add_foreign_key "security_events", "users"
  add_foreign_key "sessions", "brands"
  add_foreign_key "sessions", "credentials"
  add_foreign_key "sessions", "users"
end
