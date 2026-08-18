require "test_helper"

module Profiles
  class LanguagesTest < ActiveSupport::TestCase
    test "exposes a config-driven taxonomy with labels" do
      assert Languages.valid_code?("en")
      assert_equal "English", Languages.label_for("en")
      assert_not Languages.valid_code?("zz")
    end

    test "normalize rejects non-arrays and over-long lists" do
      assert_includes Languages.normalize("en").errors, "must be an array"
      too_many = Array.new(Languages::MAX_ENTRIES + 1) { { "code" => "en" } }
      assert_includes Languages.normalize(too_many).errors, "cannot have more than #{Languages::MAX_ENTRIES} entries"
    end

    test "normalize rejects unknown codes and invalid proficiency" do
      assert_includes Languages.normalize([ { "code" => "zz" } ]).errors, "contains an unsupported language code"
      assert_includes Languages.normalize([ { "code" => "en", "proficiency" => "expert" } ]).errors,
        "contains an invalid proficiency"
    end

    test "normalize dedups by code, lowercases, and caps a single primary" do
      result = Languages.normalize([
        { "code" => "EN", "proficiency" => "fluent", "primary" => true },
        { "code" => "en", "proficiency" => "native" }
      ])
      assert_empty result.errors
      assert_equal 1, result.entries.size
      assert_equal "en", result.entries.first.fetch("code")

      multiple_primary = Languages.normalize([
        { "code" => "en", "primary" => true }, { "code" => "fr", "primary" => true }
      ])
      assert_includes multiple_primary.errors, "can have at most one primary language"
    end

    test "serialize attaches labels and drops unknown codes" do
      serialized = Languages.serialize([
        { "code" => "en", "proficiency" => "fluent", "primary" => true },
        { "code" => "zz" }
      ])
      assert_equal 1, serialized.size
      assert_equal({ code: "en", label: "English", proficiency: "fluent", primary: true }, serialized.first)
    end
  end
end
