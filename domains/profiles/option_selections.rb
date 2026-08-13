module Profiles
  class OptionSelections
    class InvalidSelection < StandardError
      attr_reader :details

      def initialize(details)
        @details = details
        super("invalid profile option selections")
      end
    end

    def self.replace!(profile:, selections:)
      new(profile:, selections:).replace!
    end

    def initialize(profile:, selections:)
      @profile = profile
      @selections = selections
    end

    def replace!
      normalized = normalize_selections

      profile.with_lock do
        normalized.each do |group_key, option_codes|
          replace_group!(group_key:, option_codes:)
        end
      end

      profile.profile_option_selections.kept.includes(:profile_option, :profile_option_group)
    end

    private

    attr_reader :profile, :selections

    def normalize_selections
      invalid!(base: [ "must be an object" ]) unless selections.is_a?(Hash)

      selections.to_h.each_with_object({}) do |(raw_key, raw_codes), normalized|
        key = raw_key.to_s
        invalid!(key => [ "must be a supported option group key" ]) unless key.match?(ProfileOptionGroup::KEY_FORMAT)
        invalid!(key => [ "must be an array" ]) unless raw_codes.is_a?(Array)

        invalid!(key => [ "must contain only string option codes" ]) unless raw_codes.all? { |code| code.is_a?(String) }

        codes = raw_codes
        invalid!(key => [ "contains an invalid option code" ]) unless codes.all? { |code| code.match?(ProfileOption::CODE_FORMAT) }

        normalized[key] = codes.uniq
      end
    end

    def replace_group!(group_key:, option_codes:)
      group = profile.brand.profile_option_groups.kept.status_active.find_by(key: group_key)
      invalid!(group_key => [ "is not enabled for this brand" ]) if group.blank?
      invalid!(group_key => [ "allows at most #{group.max_selections} selections" ]) if option_codes.size > group.max_selections

      options = group.profile_options.kept.status_active.where(code: option_codes).index_by(&:code)
      unknown_codes = option_codes - options.keys
      invalid!(group_key => [ "contains unsupported options: #{unknown_codes.join(', ')}" ]) if unknown_codes.any?

      current = profile.profile_option_selections.kept.where(profile_option_group: group).includes(:profile_option)
      current_by_code = current.index_by { |selection| selection.profile_option.code }

      current_by_code.except(*option_codes).each_value do |selection|
        selection.update!(deleted_at: Time.current)
      end

      option_codes.each do |code|
        next if current_by_code.key?(code)

        profile.profile_option_selections.create!(
          user: profile.user,
          brand: profile.brand,
          profile_option_group: group,
          profile_option: options.fetch(code)
        )
      end
    end

    def invalid!(details)
      raise InvalidSelection, details
    end
  end
end
