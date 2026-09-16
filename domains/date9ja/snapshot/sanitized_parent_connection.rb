# frozen_string_literal: true

module Date9ja
  module Snapshot
    # A second isolated read-only connection, used ONLY by the synthetic-media
    # verifier to compare `date9ja_snapshot_sanitized_media_v2` against its parent
    # `date9ja_snapshot_sanitized` for structural drift. Same safety fences as
    # Date9ja::Snapshot::Connection; never the D8N primary, never production.
    class SanitizedParentConnection < ActiveRecord::Base
      self.abstract_class = true

      def self.connect!(url:)
        Connection.assert_safe!(url)
        establish_connection(url)
        connection
      end
    end
  end
end
