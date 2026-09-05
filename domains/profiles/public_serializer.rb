module Profiles
  class PublicSerializer
    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
      @field_policy = FieldPolicy.new(brand: profile.brand)
    end

    def call
      {
        id: profile.public_id,
        photos: public_photos,
        options: public_options
      }.merge(public_profile_fields).merge(derived_public_fields)
    end

    private

    attr_reader :profile, :field_policy

    # Public scalar values, resolved once through FieldPolicy: canonical ∧
    # brand-enabled ∧ catalogue audience ceiling is :public ∧ not
    # sensitive-identity ∧ storage available. A field never serializes publicly
    # merely because D8N knows it.
    def public_profile_fields
      field_policy.public_serialized_fields.to_h do |field|
        value = if field.value_source == :languages_catalog
          Profiles::Languages.serialize(profile.languages)
        else
          profile.public_send(field.key)
        end
        [ field.key.to_sym, value ]
      end
    end

    def derived_public_fields
      fields = {}
      fields[:age] = age if field_policy.profile_enabled?("birthdate")
      if field_policy.profile_enabled?("city") || field_policy.profile_enabled?("country_code")
        fields[:location] = location
      end
      fields
    end

    # Safe, approximate location metadata only — never raw coordinates. The
    # viewer-relative `distance_km` is supplied separately by Profiles::StatusFields
    # (it depends on the viewer), so it is not duplicated here.
    def location
      city = profile.city if field_policy.profile_enabled?("city")
      country_code = profile.country_code if field_policy.profile_enabled?("country_code")
      return if city.blank? && country_code.blank?

      { city:, country_code:, precision: "approximate" }
    end

    # Only safe display derivatives of deliverable photos are exposed to other
    # users — never the raw original, its object key, or a permanent URL. Any
    # photo that is deleted, hidden, or not yet processed fails closed (omitted).
    def public_photos
      photos = if profile.profile_photos.loaded?
        profile.profile_photos.select(&:deliverable?).sort_by { |photo| [ photo.position, photo.id ] }
      else
        profile.profile_photos.deliverable.ordered.with_attached_display_image
      end

      photos.each_with_index.map do |photo, index|
        {
          # Stable, opaque photo id — the reference a viewer uses to report this
          # specific photo. Never the internal id or R2 object key.
          id: photo.public_id,
          position: photo.position,
          primary: index.zero?,
          url: photo.display_image.url(expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN),
          url_expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN.to_i
        }
      end
    end

    def age
      return if profile.birthdate.blank?

      today = Date.current
      today.year - profile.birthdate.year - ((today.month * 100 + today.day) < (profile.birthdate.month * 100 + profile.birthdate.day) ? 1 : 0)
    end

    def public_options
      selections = if profile.profile_option_selections.loaded?
        profile.profile_option_selections.select do |selection|
          selection.deleted_at.nil? && selection.profile_option_group.deleted_at.nil? &&
            selection.profile_option_group.visibility_public_profile?
        end
      else
        profile.profile_option_selections.kept
          .joins(:profile_option_group)
          .merge(ProfileOptionGroup.kept.visibility_public_profile)
          .includes(:profile_option, :profile_option_group)
      end

      selections.group_by { |selection| selection.profile_option_group.key }.transform_values do |group_selections|
        group_selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
          .map { |selection| selection.profile_option.code }
      end
    end
  end
end
