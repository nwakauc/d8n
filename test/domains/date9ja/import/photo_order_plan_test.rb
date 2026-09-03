# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    class PhotoOrderPlanTest < ActiveSupport::TestCase
      Photo = Struct.new(:source_id, :position, :is_primary, keyword_init: true) do
        def to_s = source_id
      end

      def photo(id, position: 0, primary: false)
        Photo.new(source_id: id.to_s, position:, is_primary: primary)
      end

      test "zero primary: keeps source order by [position, id]" do
        plan = PhotoOrderPlan.call([ photo(3, position: 2), photo(1, position: 0), photo(2, position: 0) ])
        assert_equal %w[1 2 3], plan.map { |e| e.photo.source_id }
        assert_equal [ 0, 1, 2 ], plan.map(&:destination_position)
      end

      test "one primary: primary goes to destination position 0" do
        plan = PhotoOrderPlan.call([ photo(1, position: 0), photo(2, position: 1, primary: true), photo(3, position: 2) ])
        assert_equal %w[2 1 3], plan.map { |e| e.photo.source_id }
        assert_equal [ 0, 1, 2 ], plan.map(&:destination_position)
      end

      test "multiple primary: fails closed" do
        assert_raises(PhotoOrderPlan::MultiplePrimary) do
          PhotoOrderPlan.call([ photo(1, primary: true), photo(2, primary: true) ])
        end
      end
    end
  end
end
