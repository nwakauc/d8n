require "test_helper"

module Geography
  class SearchTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      Geography::SouthAfricaCatalog.install!
    end

    test "raises InvalidQuery for a blank or too-short query" do
      assert_raises(Search::InvalidQuery) { Search.call(brand: @brand, query: "") }
      assert_raises(Search::InvalidQuery) { Search.call(brand: @brand, query: "s") }
      assert_raises(Search::InvalidQuery) { Search.call(brand: @brand, query: "   ") }
    end

    test "accepts a query at exactly the minimum length" do
      results = Search.call(brand: @brand, query: "za")
      assert_kind_of Array, results
    end

    test "a brand with no configured place_country_codes returns no results, never an error" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      assert_equal [], Search.call(brand: hookus, query: "sea point")
    end

    test "results are Geography::ProviderResult values with no raw coordinates exposed" do
      result = Search.call(brand: @brand, query: "sea point").sole
      assert_kind_of Geography::ProviderResult, result
      assert_not_respond_to result, :latitude
      assert_not_respond_to result, :longitude
    end
  end
end
