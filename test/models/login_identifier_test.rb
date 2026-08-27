require "test_helper"

module Identity
  class LoginIdentifierTest < ActiveSupport::TestCase
    test "normalizes and classifies email" do
      result = LoginIdentifier.call(" Ada@Example.COM ")

      assert_equal :email, result.kind
      assert_equal "ada@example.com", result.normalized_value
      assert_equal :email_password, result.auth_method
    end

    test "normalizes and classifies phone" do
      result = LoginIdentifier.call("+27 82 123 4567")

      assert_equal :phone, result.kind
      assert_equal "27821234567", result.normalized_value
      assert_equal :phone_password, result.auth_method
    end

    test "normalizes South African national and international forms through brand policy" do
      brand = Brand.create!(slug: "dateza", name: "DateZA", auth_methods: %w[phone_password])

      results = [ "0821234567", "+27821234567", "27821234567" ].map do |value|
        LoginIdentifier.call(value, brand:)
      end

      assert_equal [ "27821234567" ], results.map(&:normalized_value).uniq
      assert results.all? { |result| result.lookup_values == %w[27821234567 0821234567] }
    end

    test "rejects malformed identifiers" do
      assert_nil LoginIdentifier.call("")
      assert_nil LoginIdentifier.call("not-an-email@")
      assert_nil LoginIdentifier.call("123")
    end
  end
end
