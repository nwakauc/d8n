class AddCategoryToProfileOptions < ActiveRecord::Migration[8.1]
  # A nullable taxonomy category on individual options so a single controlled group
  # (notably `interests`) can carry categorized values (food/music/travel/…) without
  # exploding into one option group per category. Generic and reusable: any brand's
  # option group may use it or leave it null. Purely additive.
  def change
    add_column :profile_options, :category, :string, limit: 40
    add_index :profile_options, [ :profile_option_group_id, :category ],
      name: "index_profile_options_on_group_and_category",
      where: "category IS NOT NULL"
  end
end
