class CreateVerificationAssertions < ActiveRecord::Migration[8.1]
  def change
    create_table :verification_assertions do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :profile, null: true, foreign_key: true
      t.string :source_type, null: false
      t.string :source_id, null: false
      t.string :check_type, null: false
      t.string :status, null: false
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.string :reviewer_source_id
      t.jsonb :evidence, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :verification_assertions, [ :brand_id, :source_type, :source_id ], unique: true,
      name: "idx_verification_assertions_source"
    add_index :verification_assertions, [ :brand_id, :user_id, :source_type, :check_type ],
      name: "idx_verification_assertions_lookup"
  end
end
