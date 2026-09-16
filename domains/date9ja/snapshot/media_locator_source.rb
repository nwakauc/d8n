# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Resolves a source blob id to its legacy storage locator
    # ({ key:, service_name: }) from the restored snapshot's `active_storage_blobs`
    # rows (ADR 0028 §2 / MEDIA-TRANSFER.md §5).
    #
    # The locator is read ONLY here, ONLY at transfer time, and is NEVER
    # persisted in a migration table, logged, or serialized. Pass 1's PhotoSource
    # deliberately never selects `key` / `service_name`; this is the sole reader.
    #
    #   MediaLocatorSource.new(connection: Date9ja::Snapshot::Connection.connect!)
    #   MediaLocatorSource.new(rows: { "12" => { key: "abc", service_name: "cloudflare" } })  # tests
    class MediaLocatorSource
      Locator = Data.define(:key, :service_name)

      def initialize(connection: nil, rows: nil, verify_schema: true)
        raise ArgumentError, "provide connection: or rows:" if connection.nil? && rows.nil?

        @connection = connection
        @verify_schema = verify_schema
        @rows = rows && rows.transform_keys(&:to_s).transform_values do |v|
          Locator.new(key: v.fetch(:key).to_s, service_name: v.fetch(:service_name).to_s)
        end
      end

      # @return [Locator, nil]
      def call(source_blob_id)
        table.fetch(source_blob_id.to_s, nil)
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
          "WHERE a.record_type = 'Photo' AND a.name = 'image'"
        ).to_a.to_h do |row|
          r = row.transform_keys(&:to_s)
          [ r.fetch("id").to_s, Locator.new(key: r.fetch("key").to_s, service_name: r.fetch("service_name").to_s) ]
        end
      end
    end
  end
end
