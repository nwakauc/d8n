require "test_helper"

module Matching
  class EligibilityPolicyTest < ActiveSupport::TestCase
    test "is an immutable bounded input for shared eligibility" do
      policy = EligibilityPolicy.new(location_max_age: 24.hours)

      assert_equal 24.hours, policy.location_max_age
      assert_predicate policy, :frozen?
      assert_predicate policy, :location_freshness_required?
      assert_raises(ArgumentError) { EligibilityPolicy.new(location_max_age: 0.hours) }
    end

    test "a nil location_max_age means a persisted location never expires" do
      policy = EligibilityPolicy.new(location_max_age: nil)

      assert_nil policy.location_max_age
      assert_not policy.location_freshness_required?
    end

    test "brand surfaces and interactions share their configured policy" do
      hookus = Brand.new(slug: "hookus", name: "HookUs")
      dateza = Brand.new(slug: "dateza", name: "DateZA")
      hookus_contract = D8n::Platform::BrandRegistry.fetch(brand: hookus)
      dateza_contract = D8n::Platform::BrandRegistry.fetch(brand: dateza)

      assert_same hookus_contract.interaction.eligibility_policy,
        hookus_contract.surface("discovery.for_you").eligibility_policy
      assert_same hookus_contract.interaction.eligibility_policy,
        hookus_contract.surface("discovery.hook_tonight").eligibility_policy
      assert_same dateza_contract.interaction.eligibility_policy,
        dateza_contract.surface("discovery.find").eligibility_policy
    end
  end
end
