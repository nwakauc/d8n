module Geography
  # Idempotent installer for a curated, launch-scope Nigerian place catalog: the
  # best-known metros and their commonly named areas, not exhaustive national
  # coverage. Coordinates are approximate public centroids (city/area centre
  # points), not derived from any member data.
  #
  # Same install!(...) shape as Geography::SouthAfricaCatalog: platform-owned,
  # brand-agnostic reference data (brands opt in via
  # BrandContract#place_country_codes), safe to re-run, upserts by the stable
  # (parent, code) pair, never duplicates.
  module NigeriaCatalog
    COUNTRY = { code: "ng", name: "Nigeria" }.freeze

    REGIONS = {
      "lagos" => {
        name: "Lagos",
        cities: {
          "lagos" => {
            name: "Lagos", latitude: 6.4550, longitude: 3.3841,
            localities: {
              "ikeja" => { name: "Ikeja", latitude: 6.6018, longitude: 3.3515 },
              "victoria-island" => { name: "Victoria Island", latitude: 6.4281, longitude: 3.4219 },
              "ikoyi" => { name: "Ikoyi", latitude: 6.4520, longitude: 3.4340 },
              "lekki" => { name: "Lekki", latitude: 6.4698, longitude: 3.5852 },
              "ajah" => { name: "Ajah", latitude: 6.4667, longitude: 3.5667 },
              "yaba" => { name: "Yaba", latitude: 6.5095, longitude: 3.3711 },
              "surulere" => { name: "Surulere", latitude: 6.4894, longitude: 3.3550 },
              "ikorodu" => { name: "Ikorodu", latitude: 6.6194, longitude: 3.5105 },
              "festac" => { name: "Festac Town", latitude: 6.4667, longitude: 3.2833 },
              "gbagada" => { name: "Gbagada", latitude: 6.5556, longitude: 3.3928 }
            }
          }
        }
      },
      "fct" => {
        name: "Federal Capital Territory",
        cities: {
          "abuja" => {
            name: "Abuja", latitude: 9.0765, longitude: 7.3986,
            localities: {
              "wuse" => { name: "Wuse", latitude: 9.0765, longitude: 7.4700 },
              "maitama" => { name: "Maitama", latitude: 9.0870, longitude: 7.4920 },
              "garki" => { name: "Garki", latitude: 9.0333, longitude: 7.4894 },
              "asokoro" => { name: "Asokoro", latitude: 9.0333, longitude: 7.5333 },
              "gwarinpa" => { name: "Gwarinpa", latitude: 9.1108, longitude: 7.4165 },
              "kubwa" => { name: "Kubwa", latitude: 9.1500, longitude: 7.3333 }
            }
          }
        }
      },
      "rivers" => {
        name: "Rivers",
        cities: {
          "port-harcourt" => {
            name: "Port Harcourt", latitude: 4.8156, longitude: 7.0498,
            localities: {
              "gra" => { name: "Old GRA", latitude: 4.8100, longitude: 7.0100 },
              "trans-amadi" => { name: "Trans Amadi", latitude: 4.8000, longitude: 7.0300 }
            }
          }
        }
      },
      "oyo" => {
        name: "Oyo",
        cities: {
          "ibadan" => {
            name: "Ibadan", latitude: 7.3775, longitude: 3.9470,
            localities: {
              "bodija" => { name: "Bodija", latitude: 7.4333, longitude: 3.9000 },
              "dugbe" => { name: "Dugbe", latitude: 7.3833, longitude: 3.8833 }
            }
          }
        }
      },
      "kano" => {
        name: "Kano",
        cities: {
          "kano" => {
            name: "Kano", latitude: 12.0022, longitude: 8.5920,
            localities: {}
          }
        }
      },
      "enugu" => {
        name: "Enugu",
        cities: {
          "enugu" => {
            name: "Enugu", latitude: 6.5244, longitude: 7.5186,
            localities: {}
          }
        }
      },
      "kaduna" => {
        name: "Kaduna",
        cities: {
          "kaduna" => {
            name: "Kaduna", latitude: 10.5222, longitude: 7.4383,
            localities: {}
          }
        }
      }
    }.freeze

    # A deliberately far-away centroid (equatorial Atlantic, well over 500km from
    # every real Nigerian place in this catalog) for members who are honestly not
    # in Nigeria and have no accurate local option. Mirrors
    # SouthAfricaCatalog::OUTSIDE_COUNTRY_FALLBACK: it satisfies the
    # location-required publication invariant without fabricating a plausible
    # nearby coordinate, and ordinary max_distance_km filtering then naturally
    # excludes them from every real candidate's distance-matched pool.
    OUTSIDE_COUNTRY_FALLBACK = {
      code: "outside-nigeria", name: "Outside Nigeria", latitude: 0.0, longitude: -10.0
    }.freeze

    def self.install!
      country = upsert!(kind: "country", parent: nil, code: COUNTRY.fetch(:code), name: COUNTRY.fetch(:name),
        country_code: "NG", latitude: 9.0820, longitude: 8.6753)

      upsert!(
        kind: "region", parent: country, code: OUTSIDE_COUNTRY_FALLBACK.fetch(:code),
        name: OUTSIDE_COUNTRY_FALLBACK.fetch(:name), country_code: "NG",
        latitude: OUTSIDE_COUNTRY_FALLBACK.fetch(:latitude), longitude: OUTSIDE_COUNTRY_FALLBACK.fetch(:longitude)
      )

      REGIONS.each do |region_code, region|
        region_row = upsert!(
          kind: "region", parent: country, code: region_code, name: region.fetch(:name), country_code: "NG",
          latitude: region.fetch(:cities).values.first.fetch(:latitude),
          longitude: region.fetch(:cities).values.first.fetch(:longitude)
        )

        region.fetch(:cities).each do |city_code, city|
          city_row = upsert!(
            kind: "city", parent: region_row, code: city_code, name: city.fetch(:name), country_code: "NG",
            latitude: city.fetch(:latitude), longitude: city.fetch(:longitude)
          )

          city.fetch(:localities).each do |locality_code, locality|
            upsert!(
              kind: "locality", parent: city_row, code: locality_code, name: locality.fetch(:name),
              country_code: "NG", latitude: locality.fetch(:latitude), longitude: locality.fetch(:longitude)
            )
          end
        end
      end

      country
    end

    def self.upsert!(kind:, parent:, code:, name:, country_code:, latitude:, longitude:)
      place = Place.kept.find_or_initialize_by(parent:, code:)
      place.assign_attributes(kind:, name:, country_code:, latitude:, longitude:, status: :active)
      place.save!
      place
    end
    private_class_method :upsert!
  end
end
