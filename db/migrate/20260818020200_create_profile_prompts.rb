class CreateProfilePrompts < ActiveRecord::Migration[8.1]
  # Profile prompts (see ADR 0017): brand-configurable prompt *definitions* and a
  # member's free-text *answers*. This is a generic, reusable D8N capability — each
  # brand seeds and enables its own prompt set (text, category, ordering) exactly
  # like the profile_options taxonomy; nothing is hardcoded to HookUs. Prompt text
  # is never stored on the answer row so copy can change without a data migration.
  def change
    # Brand-scoped prompt definitions. `key` is a stable machine identifier (copy
    # lives in `text`), unique per brand among kept rows.
    create_table :profile_prompts do |t|
      t.references :brand, null: false, foreign_key: true
      t.string :key, limit: 80, null: false
      t.string :text, limit: 160, null: false
      t.string :category, limit: 40
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_prompts, [ :brand_id, :key ],
      unique: true, where: "deleted_at IS NULL",
      name: "idx_profile_prompts_active_key"
    # Composite unique key for tenant-safe references from answers.
    add_index :profile_prompts, [ :id, :brand_id ],
      unique: true, name: "idx_profile_prompts_on_id_brand"
    add_check_constraint :profile_prompts, "\"position\" >= 0",
      name: "chk_profile_prompts_position"

    # A member's free-text answer to a brand prompt. One kept answer per
    # (profile, prompt); the writer caps the number of answers per profile.
    #
    # The answer belongs to a single Profile, which is the authoritative owner of
    # both the member (user) and the brand — so user_id is NOT denormalized here.
    # brand_id IS carried, solely because the tenant-safe composite foreign keys
    # below (profile / prompt within the SAME brand) require it as an integrity
    # guarantee, mirroring profile_option_selections.
    create_table :profile_prompt_answers do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: false
      t.references :profile_prompt, null: false, foreign_key: false
      t.text :answer, null: false
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_prompt_answers, [ :profile_id, :profile_prompt_id ],
      unique: true, where: "deleted_at IS NULL",
      name: "idx_profile_prompt_answers_active"
    add_check_constraint :profile_prompt_answers, "\"position\" >= 0",
      name: "chk_profile_prompt_answers_position"

    # Tenant-safe composite foreign keys: an answer can only reference a profile and
    # a prompt within its own brand (mirrors profile_option_selections).
    add_foreign_key :profile_prompt_answers, :profiles,
      column: [ :profile_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_profile_prompt_answers_profile_tenant"
    add_foreign_key :profile_prompt_answers, :profile_prompts,
      column: [ :profile_prompt_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_profile_prompt_answers_prompt_tenant"
  end
end
