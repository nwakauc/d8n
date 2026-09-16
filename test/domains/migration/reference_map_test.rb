require "test_helper"

module Migration
  class ReferenceMapTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @other_brand = Brand.create!(slug: "dateza", name: "DateZA")
      @user = User.create!
      @profile = profile_for(@brand, @user)
    end

    def bind(**overrides)
      defaults = {
        source_system: "date9ja", source_entity: "profile", source_id: "4021",
        destination: @profile, brand: @brand, importer_version: "v1"
      }
      ReferenceMap.bind!(**defaults.merge(overrides))
    end

    test "binds a source key to a brand-owned destination and resolves it" do
      reference = bind

      assert_equal @profile, ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: "4021")
      assert_equal reference, ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile", source_id: "4021")
      assert_equal @brand.id, reference.brand_id
    end

    test "normalizes source key casing and whitespace" do
      bind
      resolved = ReferenceMap.resolve(source_system: " Date9ja ", source_entity: "PROFILE", source_id: " 4021 ")

      assert resolved
      assert_equal @profile, resolved.destination
    end

    test "repeating the identical bind is idempotent and refreshes only metadata" do
      first = bind(fingerprint: "fp-1")

      assert_no_difference -> { LegacyReference.count } do
        second = bind(fingerprint: "fp-2", importer_version: "v2")
        assert_equal first.id, second.id
      end

      first.reload
      assert_equal "fp-2", first.source_fingerprint
      assert_equal "v2", first.importer_version
      assert_equal @profile.id, first.destination_id
    end

    test "the same source key cannot be rebound to a different destination" do
      bind
      other_profile = profile_for(@brand, User.create!)

      error = assert_raises(ReferenceMap::ImmutableBinding) { bind(destination: other_profile) }
      assert_not_includes error.message, "4021"
      assert_equal @profile, ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: "4021")
    end

    test "the same destination cannot be claimed by a different source key" do
      bind

      assert_raises(ReferenceMap::DestinationConflict) { bind(source_id: "9999") }
      assert_equal 1, LegacyReference.where(destination_type: "Profile", destination_id: @profile.id).count
    end

    test "a numeric source id may map to different destinations under different entity types" do
      bind(source_entity: "profile")
      membership = BrandMembership.find_by!(user: @user, brand: @brand)

      assert_nothing_raised do
        bind(source_entity: "membership", destination: membership)
      end
      assert_equal 2, LegacyReference.for_source("date9ja").where(source_id: "4021").count
    end

    test "rejects an unknown source system without writing" do
      assert_no_difference -> { LegacyReference.count } do
        assert_raises(ReferenceMap::UnknownSourceSystem) { bind(source_system: "friendster") }
      end
    end

    test "rejects an unknown destination type" do
      # Brand is a real persisted record but not a bindable destination.
      assert_raises(ReferenceMap::UnknownDestinationType) do
        bind(source_entity: "brand", destination: @other_brand)
      end
    end

    test "rejects a nil destination" do
      assert_raises(ReferenceMap::Error) { bind(destination: nil) }
    end

    test "requires a brand for a brand-owned destination" do
      assert_raises(ReferenceMap::MissingBrand) { bind(brand: nil) }
    end

    test "rejects a cross-brand binding before persistence" do
      assert_no_difference -> { LegacyReference.count } do
        assert_raises(ReferenceMap::BrandMismatch) { bind(brand: @other_brand) }
      end
    end

    test "binds a platform-owned destination with no brand and rejects a brand" do
      reference = ReferenceMap.bind!(
        source_system: "date9ja", source_entity: "user", source_id: "77",
        destination: @user, importer_version: "v1"
      )
      assert_nil reference.brand_id
      assert_equal @user, reference.destination

      assert_raises(ReferenceMap::Error) do
        ReferenceMap.bind!(
          source_system: "date9ja", source_entity: "user", source_id: "78",
          destination: User.create!, brand: @brand, importer_version: "v1"
        )
      end
    end

    test "a failure inside the bind transaction leaves the prior state intact" do
      reference = bind(importer_version: "v1")

      # A too-long fingerprint fails validation during the metadata refresh,
      # after assert_same_binding! has passed — the whole bind! must roll back.
      assert_no_difference -> { LegacyReference.count } do
        assert_raises(ActiveRecord::RecordInvalid) do
          bind(importer_version: "v2", fingerprint: "x" * 300)
        end
      end

      reference.reload
      assert_equal "v1", reference.importer_version
      assert_nil reference.source_fingerprint
    end

    test "dangling reports bindings whose D8N record is gone" do
      bind
      ProfilePreference.where(profile: @profile).delete_all
      Profile.where(id: @profile.id).delete_all

      dangling = ReferenceMap.dangling(source_system: "date9ja")
      assert_equal 1, dangling.size
      assert_not dangling.first.resolvable?
    end

    private

    def profile_for(brand, user)
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "P#{user.id}", birthdate: 27.years.ago.to_date, gender: "woman"
      )
    end
  end

  # The lost-race recovery path, reproduced DETERMINISTICALLY.
  #
  # `bind!` opens a transaction, pre-checks with `locate`, and calls `claim`
  # when the key looks free. `claim` inserts. If a concurrent claimer commits
  # that key in between, the INSERT violates a unique index, and in PostgreSQL a
  # failed statement aborts the enclosing transaction -- so `claim`'s documented
  # recovery (re-run `locate`, let `assert_same_binding!` classify the outcome)
  # can only run if the INSERT is scoped to its own savepoint.
  #
  # Reproducing this needs a real `ActiveRecord::RecordNotUnique` from the
  # database. Staging the conflict *before* `bind!` does NOT reproduce it: the
  # model's uniqueness validations (`legacy_reference.rb:20-23`) SELECT first and
  # raise `RecordInvalid` without ever issuing the failing INSERT, leaving the
  # transaction clean. That is also why the thread-racing test below only fails
  # intermittently -- it needs two writers to clear validation together.
  #
  # So these tests insert the competing row from a SECOND CONNECTION inside a
  # `before_create` hook: our validations have already passed, the competing row
  # is committed, and our INSERT hits the index. The thread is joined before the
  # hook returns, so there is no scheduling dependence and no sleep.
  class ReferenceMapLostRaceTest < ActiveSupport::TestCase
    # The competing row is committed by another connection, so it is not covered
    # by a test transaction; this class cleans up explicitly.
    self.use_transactional_tests = false

    setup do
      @brand = Brand.create!(slug: "date9ja-race-#{SecureRandom.hex(4)}", name: "Race")
      @user = User.create!
      @other_user = User.create!
      @profile = profile_for(@brand, @user)
      @other_profile = profile_for(@brand, @other_user)
    end

    teardown do
      LegacyReference.where(source_system: "date9ja", source_id: [ KEY, OTHER_KEY ]).delete_all
      LegacyReference.where(brand: @brand).delete_all
      Profile.where(brand: @brand).delete_all
      BrandMembership.where(brand: @brand).delete_all
      @brand.destroy!
      [ @user, @other_user ].each { |u| u&.destroy! }
    end

    KEY = "race-4021"
    OTHER_KEY = "race-9999"

    def bind(**overrides)
      defaults = {
        source_system: "date9ja", source_entity: "profile", source_id: KEY,
        destination: @profile, brand: @brand, importer_version: "v1"
      }
      ReferenceMap.bind!(**defaults.merge(overrides))
    end

    # Commits `attrs` from another connection at the exact moment our own
    # transaction has validated and is about to INSERT.
    def with_concurrent_claimer(**attrs)
      fired = false
      # ActiveSupport instance_execs a proc callback on the RECORD, so every
      # value the claimer needs is captured as a local here, not read from @ivars.
      row = {
        source_system: "date9ja", source_entity: "profile", destination_type: "Profile",
        brand_id: @brand.id, importer_version: "winner"
      }.merge(attrs)
      hook = lambda do |_record|
        next if fired

        fired = true
        Thread.new do
          LegacyReference.connection_pool.with_connection { LegacyReference.create!(**row) }
        end.join
      end
      LegacyReference.set_callback(:create, :before, hook)
      yield
      assert fired, "the staged claimer never fired -- the race was not reproduced"
    ensure
      LegacyReference.skip_callback(:create, :before, hook, raise: false)
    end

    test "the staging really does drive claim into a database unique violation" do
      # Without the savepoint this INSERT is what aborts bind!'s transaction.
      assert_nothing_raised do
        with_concurrent_claimer(source_id: KEY, destination_id: @profile.id) { bind }
      end
      assert_equal 1, LegacyReference.where(source_id: KEY).count, "exactly one row survives"
    end

    test "a lost race against an identical binding resolves idempotently" do
      reference = nil
      with_concurrent_claimer(source_id: KEY, destination_id: @profile.id) do
        reference = bind(fingerprint: "fp-2", importer_version: "v2")
      end

      assert_equal 1, LegacyReference.where(source_id: KEY).count
      assert_equal @profile, reference.destination
      assert_equal "v2", reference.reload.importer_version, "recovery still refreshes metadata"
    end

    test "a lost race on the source key raises ImmutableBinding, not an aborted transaction" do
      error = assert_raises(ReferenceMap::ImmutableBinding) do
        with_concurrent_claimer(source_id: KEY, destination_id: @other_profile.id) { bind }
      end

      refute_match(/InFailedSqlTransaction/, error.message)
      assert_equal @other_profile.id, LegacyReference.find_by(source_id: KEY).destination_id,
        "the winner's binding is never rewritten"
    end

    test "a lost race on the destination raises DestinationConflict, not an aborted transaction" do
      error = assert_raises(ReferenceMap::DestinationConflict) do
        with_concurrent_claimer(source_id: OTHER_KEY, destination_id: @profile.id) { bind }
      end

      refute_match(/InFailedSqlTransaction/, error.message)
      refute LegacyReference.exists?(source_id: KEY), "the loser never gets a row"
    end

    test "the connection stays usable after a lost race" do
      assert_raises(ReferenceMap::ImmutableBinding) do
        with_concurrent_claimer(source_id: KEY, destination_id: @other_profile.id) { bind }
      end

      # The regression itself: before the fix the failed INSERT left the
      # transaction aborted and every statement after it raised
      # PG::InFailedSqlTransaction.
      assert_nothing_raised do
        ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile", source_id: KEY)
      end
    end

    private

    def profile_for(brand, user)
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "P#{user.id}", birthdate: 27.years.ago.to_date, gender: "woman"
      )
    end
  end

  class ReferenceMapConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "concurrent binds of the same key produce exactly one row" do
      brand = Brand.create!(slug: "date9ja-conc-#{SecureRandom.hex(4)}", name: "Conc")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "Conc", birthdate: 30.years.ago.to_date, gender: "woman"
      )
      results = Queue.new
      start = Queue.new

      threads = 4.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << ReferenceMap.bind!(
              source_system: "date9ja", source_entity: "profile", source_id: "555",
              destination: profile, brand:, importer_version: "v1"
            )
          rescue StandardError => e
            results << e
          end
        end
      end
      4.times { start << true }
      threads.each(&:join)
      outcomes = 4.times.map { results.pop }

      assert outcomes.none? { |o| o.is_a?(StandardError) }, outcomes.map(&:inspect).join("\n")
      assert_equal 1, LegacyReference.where(source_system: "date9ja", source_id: "555").count
      assert_equal 1, outcomes.map(&:id).uniq.size
    ensure
      if brand
        LegacyReference.where(brand:).delete_all
        LegacyReference.where(source_system: "date9ja", source_id: "555").delete_all
        ProfilePreference.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        brand.destroy!
        user&.destroy!
      end
    end
  end
end
