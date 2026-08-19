ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Temporarily replace a singleton (class) method with `replacement` for the
    # duration of the block, then restore the original. A dependency-free stand-in
    # for mock libraries, used to swap outbound HTTP transports in gateway specs.
    def stub_method(owner, name, replacement)
      original = owner.method(name)
      owner.define_singleton_method(name, replacement)
      yield
    ensure
      owner.define_singleton_method(name, original)
    end
  end
end
