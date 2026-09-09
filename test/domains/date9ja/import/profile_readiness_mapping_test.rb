# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    class ProfileReadinessMappingTest < ActiveSupport::TestCase
      test "name mapping takes the first token as the given name and joins the rest as the surname" do
        mapped = NameMapping.call("  Ada   Nwosu ")
        assert mapped.mapped?
        assert_equal "Ada", mapped.first_name
        assert_equal "Nwosu", mapped.last_name

        one_token = NameMapping.call("Madonna")
        assert one_token.mapped?
        assert_equal "Madonna", one_token.first_name
        assert_nil one_token.last_name

        three_token = NameMapping.call("Ada Obi Nwosu")
        assert three_token.mapped?
        assert_equal "Ada", three_token.first_name
        assert_equal "Obi Nwosu", three_token.last_name

        refute NameMapping.call(nil).mapped?
        refute NameMapping.call("   ").mapped?
      end

      test "country mapping is explicit normalized and fails closed" do
        assert_equal "NG", CountryMapping.call("  NiGeRiA ").country_code
        assert_equal "GB", CountryMapping.call("United   Kingdom").country_code
        assert_equal "US", CountryMapping.call("United States of America").country_code
        assert_equal "ZA", CountryMapping.call("south africa").country_code
        assert_equal "AE", CountryMapping.call("United Arab Emirates").country_code
        refute CountryMapping.call("UAE").mapped?
        refute CountryMapping.call("Atlantis").mapped?
        refute CountryMapping.call(nil).mapped?
      end

      test "place resolution is exact and limited to canonical Nigerian places" do
        Geography::NigeriaCatalog.install!
        Geography::SouthAfricaCatalog.install!

        assert_equal "city", PlaceResolver.call(city: "Lagos", country_code: "NG").kind
        assert_equal "lekki", PlaceResolver.call(city: "  LEKKI ", country_code: "NG").code
        assert_nil PlaceResolver.call(city: "Cape Town", country_code: "ZA")
        assert_nil PlaceResolver.call(city: "Owerri", country_code: "NG")
        assert_nil PlaceResolver.call(city: "Outside Nigeria", country_code: "GB")
      end
    end
  end
end
