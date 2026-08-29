module Geography
  # Idempotent installer for a curated, launch-scope South African place
  # catalog: a handful of major metros and their best-known suburbs/areas,
  # not exhaustive national coverage. Coordinates are approximate public
  # centroids (city/suburb centre points), not derived from any member data.
  #
  # Same install!(...) shape as Brands::DatezaInstaller/CapabilityCatalog: safe
  # to re-run, upserts by the stable (parent, code) pair, never duplicates.
  module SouthAfricaCatalog
    COUNTRY = { code: "za", name: "South Africa" }.freeze

    REGIONS = {
      "western-cape" => {
        name: "Western Cape",
        cities: {
          "cape-town" => {
            name: "Cape Town", latitude: -33.9249, longitude: 18.4241,
            localities: {
              "sea-point" => { name: "Sea Point", latitude: -33.9186, longitude: 18.3849 },
              "camps-bay" => { name: "Camps Bay", latitude: -33.9500, longitude: 18.3775 },
              "observatory" => { name: "Observatory", latitude: -33.9377, longitude: 18.4720 },
              "claremont" => { name: "Claremont", latitude: -33.9811, longitude: 18.4645 },
              "woodstock" => { name: "Woodstock", latitude: -33.9270, longitude: 18.4487 },
              "parklands" => { name: "Parklands", latitude: -33.8156, longitude: 18.4948 },
              "table-view" => { name: "Table View", latitude: -33.8236, longitude: 18.4899 },
              "bloubergstrand" => { name: "Bloubergstrand", latitude: -33.8064, longitude: 18.4552 },
              "milnerton" => { name: "Milnerton", latitude: -33.8664, longitude: 18.4989 },
              "century-city" => { name: "Century City", latitude: -33.8901, longitude: 18.5122 },
              "green-point" => { name: "Green Point", latitude: -33.9067, longitude: 18.4067 },
              "gardens" => { name: "Gardens", latitude: -33.9333, longitude: 18.4111 },
              "rondebosch" => { name: "Rondebosch", latitude: -33.9575, longitude: 18.4747 },
              "newlands" => { name: "Newlands", latitude: -33.9736, longitude: 18.4572 },
              "constantia" => { name: "Constantia", latitude: -34.0231, longitude: 18.4297 },
              "bellville" => { name: "Bellville", latitude: -33.8994, longitude: 18.6292 },
              "durbanville" => { name: "Durbanville", latitude: -33.8306, longitude: 18.6503 },
              "muizenberg" => { name: "Muizenberg", latitude: -34.1080, longitude: 18.4700 },
              "hout-bay" => { name: "Hout Bay", latitude: -34.0492, longitude: 18.3564 },
              "wynberg" => { name: "Wynberg", latitude: -34.0000, longitude: 18.4667 }
            }
          }
        }
      },
      "gauteng" => {
        name: "Gauteng",
        cities: {
          "johannesburg" => {
            name: "Johannesburg", latitude: -26.2041, longitude: 28.0473,
            localities: {
              "sandton" => { name: "Sandton", latitude: -26.1076, longitude: 28.0567 },
              "melville" => { name: "Melville", latitude: -26.1808, longitude: 28.0006 },
              "maboneng" => { name: "Maboneng", latitude: -26.2023, longitude: 28.0567 },
              "rosebank" => { name: "Rosebank", latitude: -26.1467, longitude: 28.0436 },
              "randburg" => { name: "Randburg", latitude: -26.0939, longitude: 27.9975 },
              "fourways" => { name: "Fourways", latitude: -26.0128, longitude: 28.0106 },
              "bryanston" => { name: "Bryanston", latitude: -26.0561, longitude: 28.0181 },
              "parkhurst" => { name: "Parkhurst", latitude: -26.1508, longitude: 28.0303 }
            }
          },
          "pretoria" => {
            name: "Pretoria", latitude: -25.7479, longitude: 28.2293,
            localities: {
              "hatfield" => { name: "Hatfield", latitude: -25.7487, longitude: 28.2373 },
              "brooklyn" => { name: "Brooklyn", latitude: -25.7635, longitude: 28.2378 },
              "menlyn" => { name: "Menlyn", latitude: -25.7828, longitude: 28.2769 },
              "centurion" => { name: "Centurion", latitude: -25.8603, longitude: 28.1894 }
            }
          }
        }
      },
      "kwazulu-natal" => {
        name: "KwaZulu-Natal",
        cities: {
          "durban" => {
            name: "Durban", latitude: -29.8587, longitude: 31.0218,
            localities: {
              "umhlanga" => { name: "Umhlanga", latitude: -29.7267, longitude: 31.0836 },
              "morningside" => { name: "Morningside", latitude: -29.8232, longitude: 31.0064 },
              "ballito" => { name: "Ballito", latitude: -29.5389, longitude: 31.2144 },
              "westville" => { name: "Westville", latitude: -29.8317, longitude: 30.9256 }
            }
          }
        }
      },
      "eastern-cape" => {
        name: "Eastern Cape",
        cities: {
          "gqeberha" => {
            name: "Gqeberha", latitude: -33.9608, longitude: 25.6022,
            localities: {}
          }
        }
      },
      "free-state" => {
        name: "Free State",
        cities: {
          "bloemfontein" => {
            name: "Bloemfontein", latitude: -29.0852, longitude: 26.1596,
            localities: {}
          }
        }
      }
    }.freeze

    # A deliberately far-away centroid (South Atlantic, well over 500km from
    # every real South African place in this catalog) for members who are
    # honestly not in South Africa and have no accurate local option. Selecting
    # it satisfies the location-required publication invariant without
    # fabricating a plausible nearby coordinate; ordinary max_distance_km
    # filtering (capped at ProfilePreference::MAX_DISTANCE_KM, 500) then
    # naturally excludes them from every real candidate's distance-matched
    # pool rather than silently matching them into the wrong city.
    OUTSIDE_COUNTRY_FALLBACK = {
      code: "outside-south-africa", name: "Outside South Africa", latitude: -20.0, longitude: 0.0
    }.freeze

    def self.install!
      country = upsert!(kind: "country", parent: nil, code: COUNTRY.fetch(:code), name: COUNTRY.fetch(:name),
        country_code: "ZA", latitude: 0, longitude: 0)

      upsert!(
        kind: "region", parent: country, code: OUTSIDE_COUNTRY_FALLBACK.fetch(:code),
        name: OUTSIDE_COUNTRY_FALLBACK.fetch(:name), country_code: "ZA",
        latitude: OUTSIDE_COUNTRY_FALLBACK.fetch(:latitude), longitude: OUTSIDE_COUNTRY_FALLBACK.fetch(:longitude)
      )

      REGIONS.each do |region_code, region|
        region_row = upsert!(
          kind: "region", parent: country, code: region_code, name: region.fetch(:name), country_code: "ZA",
          latitude: region.fetch(:cities).values.first.fetch(:latitude),
          longitude: region.fetch(:cities).values.first.fetch(:longitude)
        )

        region.fetch(:cities).each do |city_code, city|
          city_row = upsert!(
            kind: "city", parent: region_row, code: city_code, name: city.fetch(:name), country_code: "ZA",
            latitude: city.fetch(:latitude), longitude: city.fetch(:longitude)
          )

          city.fetch(:localities).each do |locality_code, locality|
            upsert!(
              kind: "locality", parent: city_row, code: locality_code, name: locality.fetch(:name),
              country_code: "ZA", latitude: locality.fetch(:latitude), longitude: locality.fetch(:longitude)
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
