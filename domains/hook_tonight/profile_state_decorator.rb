module HookTonight
  class ProfileStateDecorator
    def self.call(viewer:, profiles:)
      active_ids = HookTonightState.live
        .where(brand_id: viewer.brand_id, profile_id: Array(profiles).map(&:id))
        .distinct
        .pluck(:profile_id)
        .to_set

      Array(profiles).each_with_object({}) do |profile, fields|
        fields[profile.id] = { hook_tonight_active: active_ids.include?(profile.id) }
      end
    end
  end
end
