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

      test "census-attested country names from the 2026-09-08 snapshot are mapped exactly" do
        {
          "Andorra" => "AD", "Angola" => "AO", "Afghanistan" => "AF", "Australia" => "AU",
          "Botswana" => "BW", "Brazil" => "BR", "Equatorial   Guinea" => "GQ", "france" => "FR",
          "Israel" => "IL", "Jamaica" => "JM", "Japan" => "JP", "Malawi" => "MW",
          "new zealand" => "NZ", "Rwanda" => "RW", "Somalia" => "SO", "Uganda" => "UG"
        }.each do |source, iso2|
          assert_equal iso2, CountryMapping.call(source).country_code, "#{source} -> #{iso2}"
        end

        # Still deliberately unmapped: a subdivision and an apparent typo are not
        # repaired — that would be a guess.
        refute CountryMapping.call("California").mapped?
        refute CountryMapping.call("nigeri").mapped?
      end

      test "interest mapping is explicit, order-preserving, and quarantines the unknown" do
        out = InterestMapping.call([ "Afro Beats", "Soccer", "reading", "quantum basket weaving" ])
        assert_equal :partial, out.status
        assert_equal %w[afrobeats football reading], out.codes

        assert InterestMapping.call([]).absent?
        assert InterestMapping.call([ "quantum basket weaving" ]).unmapped?
        assert_empty InterestMapping.call([ "quantum basket weaving" ]).codes
      end

      test "relationship value mapping is explicit and fails closed" do
        out = RelationshipValueMapping.call([ "Honesty", "sense of humour", "vibes" ])
        assert_equal :partial, out.status
        assert_equal %w[honesty humour], out.codes
        assert RelationshipValueMapping.call([ "vibes" ]).unmapped?
        assert RelationshipValueMapping.call(nil).absent?
      end

      test "dealbreaker mapping is lossless per element and fails closed" do
        out = DealbreakerMapping.call([ "Smoking", "doesn't want kids", "long distance", "bad vibes" ])
        assert_equal :partial, out.status
        assert_equal %w[smoking does_not_want_children long_distance], out.codes
        assert DealbreakerMapping.call([ "bad vibes" ]).unmapped?
        assert DealbreakerMapping.call([]).absent?
      end

      test "curated mappings only ever emit codes their D8N option group defines" do
        {
          InterestMapping => Profiles::CapabilityCatalog::INTERESTS.fetch(:options).map { |o| o.fetch(:code) },
          RelationshipValueMapping =>
            Profiles::CapabilityCatalog::OPTION_CAPABILITIES.fetch("relationship_values").fetch(:options).keys,
          DealbreakerMapping =>
            Profiles::CapabilityCatalog::OPTION_CAPABILITIES.fetch("dealbreakers").fetch(:options).keys
        }.each do |mapping, catalogue_codes|
          emitted = mapping::ALIASES.values.uniq
          assert_empty(emitted - catalogue_codes, "#{mapping} emits a code its option group does not define")
        end
      end

      test "Nigerian state mapping is a closed 37-value allowlist that fails closed" do
        assert_equal "Imo", NigerianStateMapping.call("  imo ").state
        assert_equal "Akwa Ibom", NigerianStateMapping.call("Akwa-Ibom").state
        assert_equal "Federal Capital Territory", NigerianStateMapping.call("Abuja").state
        assert NigerianStateMapping.call("Lagos Island").unmapped?
        assert NigerianStateMapping.call(nil).absent?
        assert_equal 36, NigerianStateMapping::STATES.size # 36 states + the FCT
      end

      test "sensitive controlled vocabularies map explicitly and quarantine the unknown" do
        assert_equal "igbo", SensitiveVocabularies::TRIBE.call("Ibo").code
        assert_equal "christian", SensitiveVocabularies::RELIGION.call("Catholic").code
        assert_equal "as", SensitiveVocabularies::GENOTYPE.call("AS").code
        assert_equal "not_open", SensitiveVocabularies::POLYGAMY_OPENNESS.call("no").code
        assert SensitiveVocabularies::TRIBE.call("Klingon").unmapped?
        assert SensitiveVocabularies::TRIBE.call(nil).absent?
      end

      test "sensitive matching-preference arrays map per element, losslessly" do
        out = SensitiveVocabularies::PREFERRED.fetch("tribe").call_many([ "Igbo", "Yoruba", "Martian" ])
        assert_equal %w[igbo yoruba], out.codes
        assert_equal :partial, out.status
      end

      test "every sensitive vocabulary only emits codes its D8N option group defines" do
        {
          "tribe" => SensitiveVocabularies::TRIBE, "ethnicity" => SensitiveVocabularies::ETHNICITY,
          "religion" => SensitiveVocabularies::RELIGION, "denomination" => SensitiveVocabularies::DENOMINATION,
          "genotype" => SensitiveVocabularies::GENOTYPE,
          "intertribal_marriage_openness" => SensitiveVocabularies::INTERTRIBAL_MARRIAGE_OPENNESS,
          "polygamy_openness" => SensitiveVocabularies::POLYGAMY_OPENNESS
        }.each do |key, mapping|
          catalogue = Profiles::CapabilityCatalog::OPTION_CAPABILITIES.fetch(key).fetch(:options).keys
          emitted = mapping.instance_variable_get(:@aliases).values.uniq
          assert_empty(emitted - catalogue, "#{key} vocabulary emits a code its option group does not define")
        end
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
