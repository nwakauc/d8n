require "test_helper"

module Profiles
  class PublicSerializerTest < ActiveSupport::TestCase
    test "exposes derived age and public options without private source fields" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)
      private_group = ProfileOptionGroup.create!(
        brand:, key: "private_note", label: "Private", visibility: :owner_only
      )
      private_option = ProfileOption.create!(
        brand:, profile_option_group: private_group, code: "hidden", label: "Hidden"
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name: "Ada", birthdate: 25.years.ago.to_date
      )
      OptionSelections.replace!(profile:, selections: { intents: [ "hookups" ], private_note: [ "hidden" ] })

      payload = PublicSerializer.call(profile:)

      assert_equal 25, payload.fetch(:age)
      assert_equal [ "hookups" ], payload.fetch(:options).fetch("intents")
      assert_not payload.fetch(:options).key?("private_note")
      assert_not payload.key?(:birthdate)
      assert_not payload.key?(:user_id)
    end
  end
end
