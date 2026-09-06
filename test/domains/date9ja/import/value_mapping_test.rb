# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    # The decode tables are the one place a legacy code becomes a member-facing
    # D8N value, so every entry is asserted against the legacy enum it claims to
    # come from, and every code WITHOUT an approved destination is asserted to
    # fail closed rather than land on a near-enough option.
    class ValueMappingTest < ActiveSupport::TestCase
      test "gender decodes the legacy enum exactly" do
        # api/app/models/user.rb: enum :gender, { man: 0, woman: 1 }
        assert_equal "man", ValueMapping.gender(0).value
        assert_equal "woman", ValueMapping.gender(1).value
        assert ValueMapping.gender(0).ok?
      end

      test "interested_in uses the same vocabulary as gender, so discovery can match" do
        assert_equal [ "man" ], ValueMapping.interested_in(0).value
        assert_equal [ "woman" ], ValueMapping.interested_in(1).value

        genders = ValueMapping::GENDER.values.sort
        interests = ValueMapping::INTERESTED_IN.values.flatten.uniq.sort
        assert_equal genders, interests,
          "EligibilityScope compares these two verbatim; a divergence matches nothing"
      end

      test "a member seeking their own gender is an ordinary value, not an anomaly" do
        # Some members are gay. The reciprocal pair man/man decodes exactly like
        # any other and carries no special status anywhere in the mapping.
        assert_equal "man", ValueMapping.gender(0).value
        assert_equal [ "man" ], ValueMapping.interested_in(0).value
        assert ValueMapping.interested_in(0).ok?
      end

      test "a NULL source column is absent, which is not the same as unmapped" do
        outcome = ValueMapping.gender(nil)

        assert outcome.absent?
        refute outcome.unmapped?
        assert_nil outcome.value
      end

      test "a real code with no approved destination is unmapped, never guessed" do
        # relationship_intention 1 = courtship, 3 = dating, 5 = activity_partner.
        # None has a D8N counterpart that means the same thing (D-5 open).
        [ 1, 3, 5 ].each do |code|
          outcome = ValueMapping.lookup("relationship_intent", code)
          assert outcome.unmapped?, "code #{code} must not be folded onto a near-enough option"
          assert_nil outcome.value
          assert_equal code, outcome.code
        end
      end

      test "relationship_intent maps only the unambiguous legacy codes" do
        assert_equal "marriage", ValueMapping.lookup("relationship_intent", 0).value
        assert_equal "long_term_relationship", ValueMapping.lookup("relationship_intent", 2).value
        assert_equal "friendship", ValueMapping.lookup("relationship_intent", 4).value
      end

      test "children_count answers has_children without being treated as a number" do
        # enum :children_count, { none: 0, one: 1, two: 2, three_or_more: 3 }
        assert_equal "no", ValueMapping.lookup("has_children", 0).value
        assert_equal "yes", ValueMapping.lookup("has_children", 1).value
        assert_equal "yes", ValueMapping.lookup("has_children", 2).value
        assert_equal "yes", ValueMapping.lookup("has_children", 3).value,
          "code 3 means three_or_more; it must not be read as the number 3"
      end

      test "wants_children maps yes and no but never decides what open meant" do
        assert_equal "yes", ValueMapping.lookup("wants_children", 0).value
        assert_equal "no", ValueMapping.lookup("wants_children", 1).value
        assert ValueMapping.lookup("wants_children", 2).unmapped?,
          "legacy `open` could be maybe or open_to_partner_with_children (D-6)"
      end

      test "numeric strings decode identically to integers" do
        assert_equal "woman", ValueMapping.gender("1").value
        assert_equal "man", ValueMapping.gender(" 0 ").value
      end

      test "a non-numeric value is never coerced into a code" do
        [ "woman", "man", "0.5", "abc", "", "  ", "1a" ].each do |value|
          outcome = ValueMapping.gender(value)
          refute outcome.ok?, "#{value.inspect} must not decode to a gender"
        end
      end

      test "every mapped destination is a real option in the shared catalogue" do
        groups = Profiles::CapabilityCatalog::OPTION_CAPABILITIES

        { "relationship_intent" => ValueMapping::RELATIONSHIP_INTENT,
          "has_children" => ValueMapping::HAS_CHILDREN,
          "wants_children" => ValueMapping::WANTS_CHILDREN }.each do |group_key, table|
          codes = groups.fetch(group_key)[:options].keys
          table.each_value do |mapped|
            assert_includes codes, mapped, "#{group_key} has no option #{mapped.inspect}"
          end
        end
      end

      test "an unknown field name fails closed rather than returning nothing" do
        assert_raises(ArgumentError) { ValueMapping.lookup("tribe", 0) }
      end
    end
  end
end
