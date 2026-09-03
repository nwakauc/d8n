# frozen_string_literal: true

require "uri"

module Date9ja
  module Snapshot
    # Dedicated, isolated ActiveRecord connection to a RESTORED SCRATCH copy of a
    # Date9ja backup. Never a live production connection (DECISIONS.md, import
    # execution model). Abstract: nothing connects at boot — a connection is
    # established only when `connect!` is called explicitly by the rehearsal task.
    #
    # Safety fences (fail closed):
    #   - the target URL must be set explicitly (no default / no fallback to
    #     D8N's own database config);
    #   - it must be a postgresql URL naming a database;
    #   - production-looking names/hosts are rejected;
    #   - D8N's own primary database is rejected (never import from ourselves).
    class Connection < ActiveRecord::Base
      self.abstract_class = true

      ENV_KEY = "DATE9JA_SNAPSHOT_DATABASE_URL"

      # A substring anywhere in the database name or host aborts the run. Kept
      # deliberately small and obvious rather than an allowlist of local hosts —
      # the operator points this at a scratch restore they just created.
      FORBIDDEN_FRAGMENTS = %w[prod production live].freeze

      class UnsafeConfiguration < StandardError; end

      Config = Data.define(:adapter, :host, :database)

      def self.connect!(url: ENV.fetch(ENV_KEY, nil))
        assert_runtime_safe!
        assert_safe!(url)
        establish_connection(url)
        connection
      end

      def self.assert_runtime_safe!
        return if Rails.env.test? && throwaway_primary_database?

        raise UnsafeConfiguration, "identity rehearsal requires a throwaway test database"
      end

      # Raises UnsafeConfiguration unless `url` names a safe scratch snapshot DB.
      def self.assert_safe!(url)
        raise UnsafeConfiguration, "#{ENV_KEY} is not set" if url.to_s.strip.empty?

        cfg = parse(url)

        unless cfg.adapter.to_s.start_with?("postgres")
          raise UnsafeConfiguration, "snapshot URL must be a postgresql connection"
        end
        raise UnsafeConfiguration, "snapshot URL does not name a database" if cfg.database.to_s.strip.empty?

        haystack = "#{cfg.database} #{cfg.host}".downcase
        if FORBIDDEN_FRAGMENTS.any? { |fragment| haystack.include?(fragment) }
          raise UnsafeConfiguration, "refusing a production-looking snapshot target"
        end

        raise UnsafeConfiguration, "refusing to read from D8N's own database" if own_primary?(cfg)

        true
      end

      def self.parse(url)
        uri = URI.parse(url)
        query = URI.decode_www_form(uri.query.to_s).to_h
        if (query.keys & %w[dbname host hostaddr service]).any?
          raise UnsafeConfiguration, "snapshot URL contains an unsafe target override"
        end

        Config.new(
          adapter: uri.scheme.to_s,
          host: decode_component(query.fetch("host", uri.host.to_s)),
          database: decode_component(query.fetch("dbname", uri.path.to_s.sub(%r{\A/}, "")))
        )
      rescue URI::InvalidURIError, ArgumentError
        raise UnsafeConfiguration, "snapshot URL is not a valid URL"
      end
      private_class_method :parse

      def self.decode_component(value)
        URI::DEFAULT_PARSER.unescape(value.to_s)
      end
      private_class_method :decode_component

      def self.throwaway_primary_database?
        database = ActiveRecord::Base.connection_db_config.configuration_hash[:database].to_s
        database.match?(/\Ad8n_date9ja_rehearsal(?:_[a-z0-9_]+)?\z/)
      rescue StandardError
        false
      end
      private_class_method :throwaway_primary_database?

      def self.own_primary?(cfg)
        primary = ActiveRecord::Base.connection_db_config.configuration_hash
        same_db = primary[:database].to_s == cfg.database
        same_host = primary[:host].to_s == cfg.host || (primary[:host].nil? && %w[localhost 127.0.0.1 ::1].include?(cfg.host))
        same_db && (same_host || cfg.host.empty?)
      rescue StandardError
        false
      end
      private_class_method :own_primary?
    end
  end
end
