module Analytics
  module EventTypes
    DEFINITIONS = {
      "member.registered" => { properties: [] },
      "profile.published" => { properties: [] }
    }.transform_values { |definition| definition.freeze }.freeze

    module_function

    def known?(event_type)
      DEFINITIONS.key?(event_type.to_s)
    end

    def allowed_properties(event_type)
      DEFINITIONS.fetch(event_type.to_s).fetch(:properties)
    end
  end
end
