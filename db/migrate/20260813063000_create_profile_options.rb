class CreateProfileOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_option_groups do |t|
      t.references :brand, null: false, foreign_key: true
      t.string :key, null: false, limit: 80
      t.string :label, null: false, limit: 120
      t.integer :cardinality, null: false, default: 0
      t.integer :max_selections, null: false, default: 1
      t.integer :visibility, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_option_groups, [ :brand_id, :key ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_option_groups_active_key"
    add_index :profile_option_groups, [ :id, :brand_id ],
      unique: true,
      name: "idx_profile_option_groups_id_brand"
    add_check_constraint :profile_option_groups, "max_selections > 0",
      name: "chk_profile_option_groups_max_selections"
    add_check_constraint :profile_option_groups, "position >= 0",
      name: "chk_profile_option_groups_position"

    create_table :profile_options do |t|
      t.references :profile_option_group, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.string :code, null: false, limit: 80
      t.string :label, null: false, limit: 120
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_options, [ :profile_option_group_id, :code ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_options_active_code"
    add_index :profile_options, [ :id, :profile_option_group_id, :brand_id ],
      unique: true,
      name: "idx_profile_options_id_group_brand"
    add_check_constraint :profile_options, "position >= 0", name: "chk_profile_options_position"
    add_foreign_key :profile_options, :profile_option_groups,
      column: [ :profile_option_group_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_profile_options_group_tenant"

    create_table :profile_option_selections do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :profile_option_group, null: false, foreign_key: true
      t.references :profile_option, null: false, foreign_key: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_option_selections,
      [ :profile_id, :profile_option_group_id, :profile_option_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_option_selections_active"
    add_index :profile_option_selections, [ :brand_id, :profile_option_group_id ]
    add_foreign_key :profile_option_selections, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_option_selections_profile_tenant"
    add_foreign_key :profile_option_selections, :profile_option_groups,
      column: [ :profile_option_group_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_option_selections_group_tenant"
    add_foreign_key :profile_option_selections, :profile_options,
      column: [ :profile_option_id, :profile_option_group_id, :brand_id ],
      primary_key: [ :id, :profile_option_group_id, :brand_id ],
      name: "fk_option_selections_option_tenant"
  end
end
