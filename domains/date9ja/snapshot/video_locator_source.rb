# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Resolves a source blob id to its legacy storage locator
    # ({ key:, service_name: }) for the Date9ja `ProfileVideo` `video`
    # attachment graph, from the restored snapshot's `active_storage_blobs` rows
    # (ADR 0029 §4). The video analogue of Date9ja::Snapshot::MediaLocatorSource
    # — deliberately a SEPARATE class so Pass-1 VideoSource stays metadata-only
    # and never learns the locator.
    #
    # The locator is read ONLY here, ONLY at transfer time, and is NEVER
    # persisted in a migration table, logged, or serialized.
    #
    #   VideoLocatorSource.new(connection: Date9ja::Snapshot::Connection.connect!)
    #   VideoLocatorSource.new(rows: { "12" => { key: "abc", service_name: "cloudflare" } }) # tests
    class VideoLocatorSource
      Locator = Data.define(:key, :service_name)

      VIDEO_RECORD_TYPE = "ProfileVideo"
      VIDEO_ATTACHMENT_NAME = "video"

      def initialize(connection: nil, rows: nil, verify_schema: true)
        raise ArgumentError, "provide connection: or rows:" if connection.nil? && rows.nil?

        @connection = connection
        @verify_schema = verify_schema
        @rows = rows && rows.transform_keys(&:to_s).transform_values do |v|
          Locator.new(key: v.fetch(:key).to_s, service_name: v.fetch(:service_name).to_s)
        end
      end

      # @return [Locator, nil] nil for an unknown blob id OR a key that fails the
      #   strict opaque-object-key grammar (fail closed — the transfer treats a
      #   nil locator as source_unavailable).
      def call(source_blob_id)
        locator = table.fetch(source_blob_id.to_s, nil)
        return nil if locator.nil?
        return nil unless Date9ja::Storage::SafeObjectKey.valid?(locator.key)

        locator
      end

      # All distinct service names in scope — used for the single-service global
      # blocker assertion.
      def service_names
        table.values.map(&:service_name).uniq
      end

      private

      def table
        @table ||= @rows || load_from_connection
      end

      def load_from_connection
        SchemaGuard.verify!(connection: @connection) if @verify_schema

        @connection.exec_query(
          "SELECT b.id, b.key, b.service_name " \
          "FROM active_storage_blobs b " \
          "JOIN active_storage_attachments a ON a.blob_id = b.id " \
          "WHERE a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}' " \
          "ORDER BY b.id"
        ).to_a.to_h do |row|
          r = row.transform_keys(&:to_s)
          [ r.fetch("id").to_s, Locator.new(key: r.fetch("key").to_s, service_name: r.fetch("service_name").to_s) ]
        end
      end
    end
  end
end
