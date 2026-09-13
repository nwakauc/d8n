class CreateCommunityQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :community_questions do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :author_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :category, null: false
      t.text :body, null: false
      t.boolean :anonymous, null: false, default: true
      t.integer :status, null: false, default: 0
      t.datetime :closes_at, null: false
      t.bigint :selected_answer_id
      t.datetime :selected_at
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_questions, :public_id, unique: true
    add_index :community_questions, [ :brand_id, :status, :closes_at ]
    add_index :community_questions, [ :brand_id, :author_profile_id, :created_at ]
  end
end
