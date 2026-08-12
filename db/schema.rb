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

ActiveRecord::Schema[8.0].define(version: 2026_08_12_134557) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "users", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "admin_assignments", "admin_roles"
  add_foreign_key "admin_assignments", "admin_users"
  add_foreign_key "admin_assignments", "brands"
  add_foreign_key "brand_memberships", "brands"
  add_foreign_key "brand_memberships", "users"
end
