require "test_helper"

module Migration
  class ImportContextTest < ActiveSupport::TestCase
    test "migrating? is false by default" do
      refute ImportContext.migrating?
    end

    test "as_migration sets migrating? to true for the duration of the block" do
      seen = nil
      ImportContext.as_migration { seen = ImportContext.migrating? }

      assert seen
      refute ImportContext.migrating?
    end

    test "migrating? reverts to false even if the block raises" do
      assert_raises(RuntimeError) do
        ImportContext.as_migration { raise "boom" }
      end

      refute ImportContext.migrating?
    end

    test "nested as_migration blocks do not lift suppression when the inner block exits" do
      ImportContext.as_migration do
        ImportContext.as_migration { }
        assert ImportContext.migrating?
      end
      refute ImportContext.migrating?
    end
  end
end
