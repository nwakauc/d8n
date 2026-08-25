require "test_helper"

class PlaceTest < ActiveSupport::TestCase
  test "builds a valid country/region/city/locality chain" do
    country = Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    region = Place.create!(kind: :region, parent: country, code: "western-cape", name: "Western Cape",
      country_code: "ZA", latitude: -33.9, longitude: 18.4)
    city = Place.create!(kind: :city, parent: region, code: "cape-town", name: "Cape Town",
      country_code: "ZA", latitude: -33.9249, longitude: 18.4241)
    locality = Place.create!(kind: :locality, parent: city, code: "sea-point", name: "Sea Point",
      country_code: "ZA", latitude: -33.9186, longitude: 18.3849)

    assert_equal "Sea Point, Cape Town, Western Cape", locality.display_path
    assert_equal [ city, region, country ], locality.ancestors
  end

  test "rejects a region with no parent" do
    region = Place.new(kind: :region, code: "western-cape", name: "Western Cape",
      country_code: "ZA", latitude: -33.9, longitude: 18.4)

    assert_not region.valid?
    assert_includes region.errors[:parent], "is required"
  end

  test "rejects a country with a parent" do
    country = Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    fake_country = Place.new(kind: :country, parent: country, code: "za2", name: "South Africa 2",
      country_code: "ZA", latitude: 0, longitude: 0)

    assert_not fake_country.valid?
    assert_includes fake_country.errors[:parent], "must be blank for a country"
  end

  test "rejects skipping a hierarchy level" do
    country = Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    city = Place.new(kind: :city, parent: country, code: "cape-town", name: "Cape Town",
      country_code: "ZA", latitude: -33.9, longitude: 18.4)

    assert_not city.valid?
    assert_includes city.errors[:parent], "must be a region"
  end

  test "rejects a child whose country_code does not match its parent" do
    country = Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    region = Place.new(kind: :region, parent: country, code: "western-cape", name: "Western Cape",
      country_code: "NA", latitude: -33.9, longitude: 18.4)

    assert_not region.valid?
    assert_includes region.errors[:country_code], "must match the parent place's country"
  end

  test "prevents two active countries sharing a country_code" do
    Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Place.create!(kind: :country, code: "za-dup", name: "South Africa Duplicate", country_code: "ZA",
        latitude: 0, longitude: 0)
    end
  end

  test "top_level returns only regions for the given country" do
    Geography::SouthAfricaCatalog.install!
    other_country = Place.create!(kind: :country, code: "na", name: "Namibia", country_code: "NA",
      latitude: 0, longitude: 0)
    Place.create!(kind: :region, parent: other_country, code: "khomas", name: "Khomas", country_code: "NA",
      latitude: -22.5, longitude: 17.0)

    codes = Place.top_level(country_code: "za").pluck(:code)

    assert_equal Geography::SouthAfricaCatalog::REGIONS.keys.sort, codes.sort
    assert_not_includes codes, "khomas"
  end
end
