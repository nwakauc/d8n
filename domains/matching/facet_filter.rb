module Matching
  # Applies only the facet definitions declared by the current discovery
  # surface. The engine understands reusable facet types, never product labels or
  # brand option-group keys.
  class FacetFilter
    class InvalidFilter < StandardError; end

    ONLINE_WINDOW = 10.minutes

    Filter = Data.define(:values, :definitions) do
      def initialize(values:, definitions:)
        super(values: values.stringify_keys.freeze, definitions: Array(definitions).freeze)
      end

      def none?
        values.values.none?(&:present?)
      end

      def value(parameter)
        values[parameter.to_s]
      end

      # Configured order is intentional so existing surface cursor fingerprints
      # remain stable when facet behavior is moved into configuration.
      def cursor_key
        definitions.filter_map do |definition|
          parameter = definition.fetch(:parameter).to_s
          configured_value = value(parameter)
          next unless configured_value.present?

          definition.fetch(:type).to_sym == :activity ? "#{parameter}:1" : "#{parameter}:#{configured_value}"
        end.join("|")
      end
    end

    NONE = Filter.new(values: {}, definitions: [])

    def self.parse(brand:, definitions:, params:)
      raw = params.to_h.stringify_keys
      values = Array(definitions).each_with_object({}) do |definition, parsed|
        parameter = definition.fetch(:parameter).to_s
        parsed[parameter] = parse_value(brand:, definition:, value: raw[parameter])
      end
      Filter.new(values:, definitions:)
    end

    def self.apply(scope:, brand:, filter:)
      filter.definitions.reduce(scope) do |current_scope, definition|
        value = filter.value(definition.fetch(:parameter))
        next current_scope unless value.present?

        apply_definition(scope: current_scope, brand:, definition:, value:)
      end
    end

    def self.parse_value(brand:, definition:, value:)
      case definition.fetch(:type).to_sym
      when :activity
        ActiveModel::Type::Boolean.new.cast(value) == true
      when :option_group
        parse_option_code(brand:, definition:, value:)
      else
        raise InvalidFilter, "unsupported facet"
      end
    end
    private_class_method :parse_value

    def self.parse_option_code(brand:, definition:, value:)
      code = value.to_s.strip
      return nil if code.empty?

      group_key = definition.fetch(:option_group).to_s
      raise InvalidFilter, "unknown option" unless filterable_codes(brand:, group_key:).include?(code)

      code
    end
    private_class_method :parse_option_code

    def self.apply_definition(scope:, brand:, definition:, value:)
      case definition.fetch(:type).to_sym
      when :activity
        scope.where(user_id: online_user_ids(brand:))
      when :option_group
        scope.where(id: matching_selections(
          brand:, group_key: definition.fetch(:option_group).to_s, code: value
        ))
      else
        raise InvalidFilter, "unsupported facet"
      end
    end
    private_class_method :apply_definition

    def self.matching_selections(brand:, group_key:, code:)
      ProfileOptionSelection.kept
        .where(brand:)
        .joins(:profile_option_group, :profile_option)
        .merge(ProfileOptionGroup.kept.status_active.visibility_public_profile)
        .merge(ProfileOption.kept.status_active)
        .where(profile_option_groups: { key: group_key })
        .where(profile_options: { code: })
        .select(:profile_id)
    end
    private_class_method :matching_selections

    def self.online_user_ids(brand:)
      Session.active.where(brand:, last_used_at: ONLINE_WINDOW.ago..).select(:user_id)
    end
    private_class_method :online_user_ids

    def self.filterable_codes(brand:, group_key:)
      ProfileOption.kept.status_active
        .joins(:profile_option_group)
        .merge(ProfileOptionGroup.kept.status_active.visibility_public_profile)
        .where(profile_option_groups: { brand:, key: group_key })
        .pluck(:code)
    end
    private_class_method :filterable_codes
  end
end
