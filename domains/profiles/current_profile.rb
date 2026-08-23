module Profiles
  class CurrentProfile
    IDENTITY_ATTRIBUTE_KEYS = %i[ first_name last_name ].freeze

    def self.find(user:, brand:)
      Profile.kept.find_by(user:, brand:)
    end

    def self.upsert!(user:, brand:, attributes:)
      membership = BrandMembership.kept.find_by!(user:, brand:)
      attributes = attributes.to_h.symbolize_keys
      identity_attributes = attributes.slice(*IDENTITY_ATTRIBUTE_KEYS)
      profile_attributes = attributes.except(*IDENTITY_ATTRIBUTE_KEYS)
      profile = nil

      Profile.transaction do
        user.with_lock { user.update!(identity_attributes) if identity_attributes.any? }
        profile = Profile.kept.find_or_initialize_by(user:, brand:)
        derive_initial_display_name!(profile:, user:, attributes: profile_attributes)

        if profile.persisted?
          profile.with_lock { update_profile!(profile:, membership:, attributes: profile_attributes) }
        else
          update_profile!(profile:, membership:, attributes: profile_attributes)
        end
      end

      profile
    end

    def self.derive_initial_display_name!(profile:, user:, attributes:)
      return unless profile.new_record?
      return if attributes.key?(:display_name) || user.first_name.blank?
      return unless profile.brand.profile_completion_requirements.fetch("identity_fields").include?("first_name")

      attributes[:display_name] = user.first_name
    end
    private_class_method :derive_initial_display_name!

    def self.update_profile!(profile:, membership:, attributes:)
      profile.brand_membership = membership
      profile.assign_attributes(attributes)
      profile.save!
      Publication.unpublish_if_incomplete!(profile:)
    end
    private_class_method :update_profile!
  end
end
