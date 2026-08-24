module D8n
  module Platform
    class ResponseDecorations
      def self.call(viewer:, profiles:, decorators:)
        profile_ids = Array(profiles).map(&:id)
        payloads = profile_ids.index_with { {} }

        Array(decorators).each do |decorator|
          fields_by_profile = decorator.call(viewer:, profiles:)
          profile_ids.each do |profile_id|
            payloads.fetch(profile_id).merge!(fields_by_profile.fetch(profile_id, {}))
          end
        end

        payloads
      end
    end
  end
end
