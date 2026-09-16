# frozen_string_literal: true

module Date9ja
  module Import
    # Per-entity, machine-readable, PII-free tally for one extended-history run.
    # Every source row lands in exactly one disposition and every non-import
    # carries a reason code — no unexplained loss. `to_h` contains counts and
    # reason codes only.
    class ExtendedHistoryReconciliation
      DISPOSITIONS = %i[imported already_imported skipped failed].freeze

      REASON_CODES = %w[
        already_imported
        owner_not_migrated
        actor_not_migrated
        message_not_migrated
        blank_source_id
        seed_linked
        destination_conflict
        invalid_source_row
      ].freeze

      def initialize
        @entities = Hash.new { |hash, key| hash[key] = { counts: Hash.new(0), reasons: Hash.new(0) } }
        @metrics = Hash.new(0)
      end

      # A free-form numeric tally that is not a per-row disposition — e.g. the
      # running sum of trust-event points, reconciled at the end of the run
      # against the entitlement `trust_xp` total.
      def add_metric(name, amount)
        @metrics[name.to_s] += amount
      end

      def metric(name) = @metrics[name.to_s]

      def considered(entity) = bump(entity, :considered)

      def imported!(entity)
        bump(entity, :imported)
      end

      def already_imported!(entity)
        bump(entity, :already_imported)
        reason(entity, "already_imported")
      end

      def skipped!(entity, code)
        bump(entity, :skipped)
        reason(entity, code)
      end

      def failed!(entity, code)
        bump(entity, :failed)
        reason(entity, code)
      end

      # A note that does not change the row disposition (e.g. an imported row
      # whose owner is a seed/demo account).
      def note!(entity, code)
        reason(entity, code)
      end

      def count(entity, counter) = @entities[entity][:counts][counter]

      def to_h
        totals = Hash.new(0)
        entities = @entities.sort.to_h { |entity, data| [ entity.to_s, entity_hash(data, totals) ] }
        {
          "entities" => entities,
          "totals" => DISPOSITIONS.to_h { |d| [ d.to_s, totals[d] ] }
            .merge("considered" => totals[:considered]),
          "metrics" => @metrics.dup
        }
      end

      private

      def entity_hash(data, totals)
        %i[considered imported already_imported skipped failed].each { |c| totals[c] += data[:counts][c] }
        {
          "considered" => data[:counts][:considered],
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, data[:counts][d] ] },
          "reason_codes" => data[:reasons].select { |_, n| n.positive? }.transform_keys(&:to_s)
        }
      end

      def bump(entity, counter)
        @entities[entity][:counts][counter] += 1
      end

      def reason(entity, code)
        raise ArgumentError, "unknown reason code #{code.inspect}" unless REASON_CODES.include?(code)

        @entities[entity][:reasons][code] += 1
      end
    end
  end
end
