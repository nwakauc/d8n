class AddFaithFamilyExpectationsToProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :profiles, :faith_family_expectations, :text
  end
end
