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

      test "a real code that is not in the enum domain is unmapped, never guessed" do
        # relationship_intention is a 0..5 enum. A code outside it (99) has no
        # meaning and must fail closed rather than be folded onto a neighbour.
        outcome = ValueMapping.lookup("relationship_intent", 99)
        assert outcome.unmapped?
        assert_nil outcome.value
        assert_equal 99, outcome.code
      end

      test "relationship_intent maps every legacy code (D8N contract fidelity)" do
        # enum :relationship_intention,
        #   { marriage: 0, courtship: 1, serious_relationship: 2, dating: 3,
        #     friendship: 4, activity_partner: 5 }
        assert_equal "marriage", ValueMapping.lookup("relationship_intent", 0).value
        assert_equal "courtship", ValueMapping.lookup("relationship_intent", 1).value
        assert_equal "long_term_relationship", ValueMapping.lookup("relationship_intent", 2).value
        assert_equal "dating", ValueMapping.lookup("relationship_intent", 3).value
        assert_equal "friendship", ValueMapping.lookup("relationship_intent", 4).value
        assert_equal "activity_partner", ValueMapping.lookup("relationship_intent", 5).value
      end

      test "children_count answers has_children without being treated as a number" do
        # enum :children_count, { none: 0, one: 1, two: 2, three_or_more: 3 }
        assert_equal "no", ValueMapping.lookup("has_children", 0).value
        assert_equal "yes", ValueMapping.lookup("has_children", 1).value
        assert_equal "yes", ValueMapping.lookup("has_children", 2).value
        assert_equal "yes", ValueMapping.lookup("has_children", 3).value,
          "code 3 means three_or_more; it must not be read as the number 3"
      end

      test "wants_children maps every legacy code including open" do
        assert_equal "yes", ValueMapping.lookup("wants_children", 0).value
        assert_equal "no", ValueMapping.lookup("wants_children", 1).value
        assert_equal "open", ValueMapping.lookup("wants_children", 2).value,
          "D8N added a first-class `open` option for exactly this value"
      end

      test "every other legacy preference/lifestyle enum maps totally" do
        {
          "children_count" => { 0 => "none", 1 => "one", 2 => "two", 3 => "three_or_more" },
          "family_involvement_level" => { 0 => "low", 1 => "medium", 2 => "high" },
          "commitment_timeline" => { 0 => "asap", 1 => "within_1_year", 2 => "one_to_two_years",
                                     3 => "two_to_three_years", 4 => "not_sure" },
          "marital_status" => { 0 => "single", 1 => "divorced", 2 => "widowed" },
          "education_level" => { 0 => "high_school", 1 => "diploma", 2 => "undergraduate",
                                 3 => "postgraduate", 4 => "doctorate" },
          "smoking" => { 0 => "never", 1 => "occasionally", 2 => "regularly" },
          "drinking" => { 0 => "never", 1 => "occasionally", 2 => "regularly" },
          "fitness" => { 0 => "never", 1 => "occasionally", 2 => "regularly" }
        }.each do |field, mapping|
          mapping.each do |code, value|
            assert_equal value, ValueMapping.lookup(field, code).value, "#{field}[#{code}]"
          end
          assert ValueMapping.lookup(field, 42).unmapped?, "#{field} still fails closed on an unknown code"
          assert ValueMapping.lookup(field, nil).absent?, "#{field} distinguishes absent from unmapped"
        end
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
          "wants_children" => ValueMapping::WANTS_CHILDREN,
          "children_count" => ValueMapping::CHILDREN_COUNT,
          "family_involvement_level" => ValueMapping::FAMILY_INVOLVEMENT_LEVEL,
          "commitment_timeline" => ValueMapping::COMMITMENT_TIMELINE,
          "marital_status" => ValueMapping::MARITAL_STATUS,
          "education_level" => ValueMapping::EDUCATION }.each do |group_key, table|
          codes = groups.fetch(group_key)[:options].keys
          table.each_value do |mapped|
            assert_includes codes, mapped, "#{group_key} has no option #{mapped.inspect}"
          end
        end
      end

      test "the lifestyle-frequency scalars map onto the Profile field vocabulary" do
        allowed = Profiles::FieldCatalog.allowed_values("smoking")
        ValueMapping::LIFESTYLE_FREQUENCY.each_value { |value| assert_includes allowed, value }
      end

      test "an unknown field name fails closed rather than returning nothing" do
        assert_raises(ArgumentError) { ValueMapping.lookup("tribe", 0) }
      end
    end
  end
end
