# frozen_string_literal: true

module Date9ja
  module Import
    # Pure deterministic ordering for one owner's Date9ja photos
    # (MEDIA-TRANSFER.md §11 / DECISIONS.md).
    #
    #   sort by [position, id]  -> deterministic, ties broken by id
    #   exactly one is_primary  -> that photo to destination position 0
    #   zero is_primary         -> keep source order (position 0 == effective primary)
    #   more than one is_primary -> MultiplePrimary (caller quarantines, never guesses)
    module PhotoOrderPlan
      Entry = Data.define(:photo, :destination_position)

      class MultiplePrimary < StandardError; end

      module_function

      def call(photos)
        ordered = photos.sort_by { |p| [ p.position.to_i, p.source_id.to_i ] }
        primaries = ordered.select(&:is_primary)
        raise MultiplePrimary if primaries.length > 1

        result =
          if primaries.length == 1
            primary = primaries.first
            [ primary ] + ordered.reject { |p| p.source_id == primary.source_id }
          else
            ordered
          end

        result.each_with_index.map { |photo, index| Entry.new(photo:, destination_position: index) }
      end
    end
  end
end
