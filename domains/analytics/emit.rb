module Analytics
  class Emit
    class InvalidEvent < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(event_type:, brand:, occurred_at: Time.current, user: nil, profile: nil,
                   session: nil, properties: {}, idempotency_key:)
      @event_type = event_type.to_s
      @brand = brand
      @occurred_at = occurred_at
      @user = user
      @profile = profile
      @session = session
      @properties = properties
      @idempotency_key = idempotency_key.to_s
    end

    def call
      validate!

      AnalyticsEvent.create_or_find_by!(idempotency_key:) do |event|
        event.event_id = SecureRandom.uuid
        event.event_type = event_type
        event.occurred_at = occurred_at
        event.brand = brand
        event.user = user
        event.profile = profile
        event.session = session
        event.properties = properties
      end
    rescue ActiveRecord::RecordNotUnique
      AnalyticsEvent.find_by!(idempotency_key:)
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record.errors.of_kind?(:idempotency_key, :taken)

      AnalyticsEvent.find_by!(idempotency_key:)
    end

    private

    attr_reader :event_type, :brand, :occurred_at, :user, :profile, :session,
      :properties, :idempotency_key

    def validate!
      raise InvalidEvent, "unknown event type" unless EventTypes.known?(event_type)
      raise InvalidEvent, "brand is required" if brand.blank?
      raise InvalidEvent, "idempotency key is required" if idempotency_key.blank?
      raise InvalidEvent, "properties must be a hash" unless properties.is_a?(Hash)

      allowed = EventTypes.allowed_properties(event_type)
      unknown = properties.stringify_keys.keys - allowed
      raise InvalidEvent, "unsupported event properties: #{unknown.join(', ')}" if unknown.any?

      validate_scope!
    end

    def validate_scope!
      return if user.blank? && profile.blank? && session.blank?

      raise InvalidEvent, "profile must belong to event brand" if profile.present? && profile.brand_id != brand.id
      raise InvalidEvent, "user must match profile" if profile.present? && user.present? && profile.user_id != user.id
      raise InvalidEvent, "session must belong to event brand" if session.present? && session.brand_id != brand.id
      raise InvalidEvent, "session must match user" if session.present? && user.present? && session.user_id != user.id
    end
  end
end
