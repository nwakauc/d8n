require "test_helper"

module Identity
  class PasswordRegistrationConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "concurrent signup for one identifier creates exactly one complete account" do
      brand = Brand.create!(
        slug: "password-race-#{SecureRandom.hex(6)}",
        name: "Password Race",
        auth_methods: %w[ phone_password ]
      )
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do |index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << PasswordRegistration.call(
              brand:,
              identifier: "+27 82 123 4567",
              password: "secret",
              device_name: "Race #{index}",
              ip_address: "192.0.2.#{index + 1}"
            )
          end
        end
      end

      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert_equal 1, outcomes.count(&:success?)
      assert_equal 1, outcomes.count { |result| result.error == :registration_unavailable }

      identifier = IdentityIdentifier.find_by!(kind: :phone, normalized_value: "27821234567")
      assert_nil identifier.verified_at
      assert_equal 1, Credential.password.where(identity_identifier: identifier).count
      assert_equal 1, CredentialPasswordHash.where(credential_id: identifier.credentials.password.select(:id)).count
      assert_equal 1, BrandMembership.where(brand:, user: identifier.user).count
      assert_equal 1, Session.where(brand:, user: identifier.user).count
    ensure
      if brand
        sessions = Session.where(brand:)
        credential_ids = sessions.where.not(credential_id: nil).pluck(:credential_id)
        user_ids = BrandMembership.where(brand:).pluck(:user_id)
        sessions.delete_all
        AuthAttempt.where(brand:).delete_all
        SecurityEvent.where(brand:).delete_all
        OtpChallenge.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        CredentialPasswordHash.where(credential_id: credential_ids).delete_all
        Credential.where(user_id: user_ids).delete_all
        IdentityIdentifier.where(user_id: user_ids).delete_all
        User.where(id: user_ids).delete_all
        brand.destroy!
      end
    end
  end
end
