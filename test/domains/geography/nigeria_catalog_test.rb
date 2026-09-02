require "test_helper"

module Geography
  class NigeriaCatalogTest < ActiveSupport::TestCase
    test "installs a hierarchical Nigerian place catalog idempotently" do
      assert_equal 0, Place.kept.where(country_code: "NG").count

      NigeriaCatalog.install!
      first_count = Place.kept.where(country_code: "NG").count
      assert_operator first_count, :>, 20

      assert_no_difference -> { Place.count } do
        NigeriaCatalog.install!
      end

      country = Place.kept.find_by!(country_code: "NG", kind: "country", code: "ng")
      lagos_region = Place.kept.find_by!(parent: country, code: "lagos")
      assert_equal "region", lagos_region.kind
      lagos_city = Place.kept.find_by!(parent: lagos_region, code: "lagos")
      assert_equal "city", lagos_city.kind
      assert Place.kept.exists?(parent: lagos_city, code: "lekki", kind: "locality")
    end

    test "provides an honest out-of-country fallback far from every real place" do
      NigeriaCatalog.install!

      fallback = Place.selectable.find_by!(code: "outside-nigeria")
      lagos = Place.selectable.find_by!(code: "lagos", kind: "city")

      # crude great-circle-free distance floor: >5 degrees separation
      degrees = Math.sqrt((fallback.latitude - lagos.latitude)**2 + (fallback.longitude - lagos.longitude)**2)
      assert_operator degrees, :>, 5
    end

    test "is independent from the South African catalog" do
      NigeriaCatalog.install!
      SouthAfricaCatalog.install!

      assert_equal 0, Place.kept.where(country_code: "NG", code: "cape-town").count
      assert Place.kept.exists?(country_code: "NG", code: "lagos")
      assert Place.kept.exists?(country_code: "ZA", code: "cape-town")
    end
  end
end
