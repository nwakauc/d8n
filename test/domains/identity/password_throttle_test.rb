require "test_helper"

module Identity
  class PasswordThrottleTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @other_brand = Brand.create!(slug: "dateza", name: "DateZA")
    end

    test "password_registration counts succeeded attempts toward both limits" do
      create_attempt(purpose: "password_registration", result: :succeeded, identifier: "a@example.com")

      result = PasswordThrottle.call(brand: @brand, purpose: "password_registration", identifier: "a@example.com", ip_address: "203.0.113.1")

      assert_not result.throttled?, "one prior success must not itself trip a 5/hour limit"
    end

    test "password_login does NOT count succeeded attempts (only failures throttle a login)" do
      10.times { create_attempt(purpose: "password_login", result: :succeeded, identifier: "b@example.com") }

      result = PasswordThrottle.call(brand: @brand, purpose: "password_login", identifier: "b@example.com", ip_address: "203.0.113.1")

      assert_not result.throttled?, "repeated successful logins must never throttle the same user"
    end

    test "password_registration identifier and ip limits are platform-wide (brand-independent)" do
      identifier_limit = PasswordThrottle::POLICIES.fetch("password_registration").fetch(:identifier_limit)
      (identifier_limit).times do |i|
        create_attempt(brand: i.even? ? @brand : @other_brand, purpose: "password_registration",
          result: :failed, identifier: "shared@example.com", ip_address: "198.51.100.#{i}")
      end

      result = PasswordThrottle.call(
        brand: @brand, purpose: "password_registration", identifier: "shared@example.com", ip_address: "198.51.100.99"
      )

      assert result.throttled?
      assert_equal :identifier, result.scope
    end

    test "password_login identifier limit stays brand-scoped" do
      limit = PasswordThrottle::POLICIES.fetch("password_login").fetch(:identifier_limit)
      limit.times { create_attempt(brand: @other_brand, purpose: "password_login", result: :failed, identifier: "c@example.com") }

      result = PasswordThrottle.call(brand: @brand, purpose: "password_login", identifier: "c@example.com", ip_address: "203.0.113.5")

      assert_not result.throttled?, "failures recorded against a DIFFERENT brand must not throttle this brand's login"
    end

    test "reports the ip scope once the ip ceiling (not the identifier ceiling) is what trips" do
      ip_limit = PasswordThrottle::POLICIES.fetch("password_registration").fetch(:ip_limit)
      ip_limit.times do |i|
        create_attempt(purpose: "password_registration", result: :succeeded, identifier: "distinct#{i}@example.com", ip_address: "198.51.100.7")
      end

      result = PasswordThrottle.call(
        brand: @brand, purpose: "password_registration", identifier: "brand-new@example.com", ip_address: "198.51.100.7"
      )

      assert result.throttled?
      assert_equal :ip, result.scope
      assert result.retry_after.positive?
    end

    private

    def create_attempt(purpose:, result:, identifier:, brand: @brand, ip_address: "203.0.113.9")
      AuthAttempt.create!(
        brand:, kind: :password, result:, identifier:, ip_address:,
        metadata: { purpose: }
      )
    end
  end
end
