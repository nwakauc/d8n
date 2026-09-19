module Notifications
  class DeviceRegistrar
    Result = Data.define(:registration, :created?)

    def self.register!(...)
      new(...).register!
    end

    def self.revoke!(...)
      new(...).revoke!
    end

    def self.disable!(registration:, reason:)
      registration.revoke!(reason:)
    end

    def initialize(brand:, user:, membership:, installation_id:, token: nil, platform: nil, device_name: nil)
      @brand = brand
      @user = user
      @membership = membership
      @installation_id = installation_id
      @token = token
      @platform = platform
      @device_name = device_name
    end

    def register!
      raise ArgumentError, "installation_id is required" if installation_id.blank?
      raise ArgumentError, "token is required" if token.blank?

      registration = find_existing_registration
      created = registration.new_record?
      registration.assign_attributes(
        brand:,
        user:,
        brand_membership: membership,
        installation_id:,
        token:,
        platform:,
        enabled: true,
        revoked_at: nil,
        last_seen_at: Time.current
      )
      registration.device_name = device_name if device_name.present?
      registration.save!
      Rails.logger.info(
        "device_registration_upserted brand=#{brand.slug} user_id=#{user.id} " \
        "installation_id_present=true platform=#{registration.platform} " \
        "created=#{created} device_registration_id=#{registration.public_id}"
      )
      Result.new(registration, created)
    rescue ActiveRecord::RecordNotUnique
      retry_registration_after_race
    end

    def revoke!(reason: "logout")
      registration = ::DeviceRegistration.kept.where(
        brand:, user:, brand_membership: membership, installation_id:
      ).first
      registration&.revoke!(reason:)
      registration
    end

    private

    attr_reader :brand, :user, :membership, :installation_id, :token, :platform, :device_name

    def find_existing_registration
      ::DeviceRegistration.kept.where(brand:, installation_id:).first ||
        ::DeviceRegistration.kept.where(brand:, token_digest: token_digest).first ||
        ::DeviceRegistration.new
    end

    def retry_registration_after_race
      registration = find_existing_registration
      raise unless registration.persisted?

      registration.assign_attributes(
        brand:,
        user:,
        brand_membership: membership,
        installation_id:,
        token:,
        platform:,
        enabled: true,
        revoked_at: nil,
        last_seen_at: Time.current
      )
      registration.device_name = device_name if device_name.present?
      registration.save!
      Result.new(registration, false)
    end

    def token_digest
      Identity::HmacDigest.call(purpose: "push-device-token", value: token)
    end
  end
end
