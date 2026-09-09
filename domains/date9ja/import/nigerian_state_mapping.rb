# frozen_string_literal: true

module Date9ja
  module Import
    # Date9ja `users.state_of_origin` -> canonical Nigerian state name.
    #
    # The vocabulary is FIXED and public: the 36 states of Nigeria plus the
    # Federal Capital Territory. This is a closed allowlist, so it needs no
    # review of member-entered text to be authoritative — a value that is not
    # one of the 37 is quarantined, never repaired. Case/whitespace/punctuation
    # normalized; a few unambiguous historical spellings are aliased.
    module NigerianStateMapping
      Outcome = Data.define(:status, :state) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      STATES = %w[
        Abia Adamawa Akwa\ Ibom Anambra Bauchi Bayelsa Benue Borno Cross\ River
        Delta Ebonyi Edo Ekiti Enugu Gombe Imo Jigawa Kaduna Kano Katsina Kebbi
        Kogi Kwara Lagos Nasarawa Niger Ogun Ondo Osun Oyo Plateau Rivers Sokoto
        Taraba Yobe Zamfara
      ].freeze
      FCT = "Federal Capital Territory"

      BY_KEY = STATES.each_with_object({ "fct" => FCT, "abuja" => FCT, "federal capital territory" => FCT }) do |state, acc|
        acc[state.downcase] = state
      end.merge(
        "akwa-ibom" => "Akwa Ibom", "cross-river" => "Cross River", "nassarawa" => "Nasarawa"
      ).freeze

      module_function

      def call(value)
        key = value.to_s.strip.downcase.gsub(/[.]/, "").gsub(/\s+/, " ")
        return Outcome.new(status: :absent, state: nil) if key.empty?

        state = BY_KEY[key] || BY_KEY[key.tr("-", " ")]
        state ? Outcome.new(status: :mapped, state: state) : Outcome.new(status: :unmapped, state: nil)
      end
    end
  end
end
