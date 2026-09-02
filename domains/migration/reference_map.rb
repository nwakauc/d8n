module Migration
  # The only write path to LegacyReference, and the deterministic resolver every
  # importer uses (ADR 0022). Bindings are immutable: once a source key points at
  # a destination, that never changes here.
  module ReferenceMap
    Error = Class.new(StandardError)
    UnknownSourceSystem = Class.new(Error)
    UnknownDestinationType = Class.new(Error)
    MissingBrand = Class.new(Error)
    BrandMismatch = Class.new(Error)
    # The source key already points at a different destination.
    ImmutableBinding = Class.new(Error)
    # The destination is already claimed by a different source key.
    DestinationConflict = Class.new(Error)

    Key = Data.define(:source_system, :source_entity, :source_id) do
      def to_h_attrs = { source_system:, source_entity:, source_id: }
    end

    module_function

    # Read-only. Returns the LegacyReference for this source key, or nil.
    def resolve(source_system:, source_entity:, source_id:)
      key = normalize_key(source_system:, source_entity:, source_id:)
      LegacyReference.find_by(**key.to_h_attrs)
    end

    # Read-only. Returns the bound D8N record, or nil if unbound or the record
    # has since been deleted (a reconciliation concern, not an error here).
    def resolved(source_system:, source_entity:, source_id:)
      resolve(source_system:, source_entity:, source_id:)&.destination
    end

    # Idempotently bind a source key to a D8N record. Re-binding the same key to
    # the same destination is a no-op (metadata may refresh). Re-binding to a
    # different destination raises; it never rewrites the row.
    def bind!(source_system:, source_entity:, source_id:, destination:, importer_version:,
      brand: nil, fingerprint: nil)
      key = normalize_key(source_system:, source_entity:, source_id:)
      target = classify_destination!(destination:, brand:)

      LegacyReference.transaction do
        reference = locate(key:, target:) || claim(key:, target:, importer_version:, fingerprint:)

        assert_same_binding!(existing: reference, key:, target:)
        refresh_metadata!(reference, importer_version:, fingerprint:)
        reference
      end
    end

    # Reconciliation helper: bindings whose D8N record can no longer be loaded.
    def dangling(source_system:)
      LegacyReference.for_source(source_system).reject(&:resolvable?)
    end

    # --- internals ---

    def normalize_key(source_system:, source_entity:, source_id:)
      system = source_system.to_s.strip.downcase
      raise UnknownSourceSystem, system.inspect unless SourceSystems.known?(system)

      entity = source_entity.to_s.strip.downcase
      raise Error, "invalid source entity #{entity.inspect}" unless SourceSystems.valid_entity?(entity)

      id = source_id.to_s.strip
      raise Error, "source id is required" if id.empty?

      Key.new(source_system: system, source_entity: entity, source_id: id)
    end
    private_class_method :normalize_key

    Target = Data.define(:type, :id, :brand_id)

    def classify_destination!(destination:, brand:)
      raise Error, "destination record is required" if destination.nil? || destination.id.nil?

      type = destination.class.name
      raise UnknownDestinationType, type unless DestinationTypes.known?(type)

      if DestinationTypes.brand_owned?(type)
        raise MissingBrand, "#{type} binding requires a brand" if brand.nil?
        unless destination.respond_to?(:brand_id) && destination.brand_id == brand.id
          raise BrandMismatch, "#{type}##{destination.id} does not belong to brand #{brand.id}"
        end

        Target.new(type:, id: destination.id, brand_id: brand.id)
      else
        raise Error, "#{type} is platform-owned and takes no brand" unless brand.nil?

        Target.new(type:, id: destination.id, brand_id: nil)
      end
    end
    private_class_method :classify_destination!

    # An already-persisted binding for this exact source key, or (when the source
    # key is free) a row that already owns the destination — which, since the
    # source key differs, is always a conflict.
    def locate(key:, target:)
      by_source = LegacyReference.lock.find_by(**key.to_h_attrs)
      return by_source if by_source

      by_destination = LegacyReference.lock.find_by(
        source_system: key.source_system,
        destination_type: target.type, destination_id: target.id
      )
      return unless by_destination

      raise DestinationConflict, "#{target.type}##{target.id} is already bound to #{by_destination.redacted_key}"
    end
    private_class_method :locate

    def claim(key:, target:, importer_version:, fingerprint:)
      LegacyReference.create!(
        **key.to_h_attrs,
        destination_type: target.type, destination_id: target.id, brand_id: target.brand_id,
        importer_version:, source_fingerprint: fingerprint
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent writer won the race between our locate check and this
      # insert. Re-resolve and let assert_same_binding! classify the outcome
      # (identical => idempotent, source key taken => ImmutableBinding,
      # destination taken => DestinationConflict).
      locate(key:, target:) || raise
    end
    private_class_method :claim

    def assert_same_binding!(existing:, key:, target:)
      same_source = existing.source_system == key.source_system &&
        existing.source_entity == key.source_entity && existing.source_id == key.source_id
      same_destination = existing.destination_type == target.type &&
        existing.destination_id == target.id && existing.brand_id == target.brand_id

      return if same_source && same_destination

      if same_source
        raise ImmutableBinding,
          "#{existing.redacted_key} is already bound to #{existing.destination_type}##{existing.destination_id}"
      end

      raise DestinationConflict,
        "#{target.type}##{target.id} is already bound to #{existing.redacted_key}"
    end
    private_class_method :assert_same_binding!

    def refresh_metadata!(reference, importer_version:, fingerprint:)
      attrs = { importer_version: }
      attrs[:source_fingerprint] = fingerprint unless fingerprint.nil?
      return if attrs.all? { |k, v| reference.public_send(k) == v }

      # Only mutable columns change here; reject_rebinding guards the rest.
      reference.update!(attrs)
    end
    private_class_method :refresh_metadata!
  end
end
