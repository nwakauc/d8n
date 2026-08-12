class CreateOtpChallenges < ActiveRecord::Migration[8.0]
  def change
    create_table :otp_challenges do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :identity_identifier, null: true, foreign_key: true
      t.integer :kind, null: false
      t.string :identifier, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer :attempt_count, null: false, default: 0
      t.string :ip_address
      t.text :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :otp_challenges, [ :brand_id, :identifier, :kind, :created_at ]
    add_index :otp_challenges, [ :brand_id, :identifier, :kind ],
      where: "consumed_at IS NULL",
      name: "index_otp_challenges_on_active_lookup"
  end
end
