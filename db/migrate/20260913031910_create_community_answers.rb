class CreateCommunityAnswers < ActiveRecord::Migration[8.0]
  def change
    create_table :community_answers do |t|
      t.references :community_question, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :author_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.text :body, null: false
      t.boolean :anonymous, null: false, default: false
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_answers, :public_id, unique: true
    add_index :community_answers, [ :brand_id, :community_question_id, :status, :created_at ], name: "idx_community_answers_publication"
  end
end
