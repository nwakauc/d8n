require "test_helper"
require "aws-sdk-s3"

class ManifestMediaTransferTest < ActiveSupport::TestCase
  class Store
    attr_reader :objects, :writes

    def initialize(objects = {})
      @objects, @writes = objects, []
    end

    def head_object(bucket:, key:)
      raise Aws::S3::Errors::NotFound.new(nil, "missing") unless objects.key?(key)

      true
    end

    def get_object(bucket:, key:)
      raise Aws::S3::Errors::NoSuchKey.new(nil, "missing") unless objects.key?(key)

      yield objects.fetch(key)
    end

    def put_object(bucket:, key:, body:, if_none_match:)
      raise "conditional creation required" unless if_none_match == "*"
      raise "overwrite forbidden" if objects.key?(key)

      writes << key
      objects[key] = body.read
    end
  end

  setup do
    @source = Store.new("owned" => "GOOD", "unclassified" => "KEEP")
    @destination = Store.new
    @manifest = { "version" => 1, "brand" => "date9ja", "objects" => [
      { "kind" => "photo", "source_id" => "1", "source_key" => "owned", "destination_key" => "dest",
        "byte_size" => 4, "sha256" => Digest::SHA256.hexdigest("GOOD") }
    ] }
  end

  def transfer
    Migration::ManifestMediaTransfer.new(source: @source, destination: @destination,
      source_bucket: "source", destination_bucket: "destination").call(@manifest)
  end

  test "scoped copy then rerun verifies bytes without more writes" do
    assert_equal 1, transfer.fetch(:transferred)
    second = transfer
    assert_equal 0, second.fetch(:failed)
    assert_equal 0, second.fetch(:transferred)
    assert_equal 1, second.fetch(:verified_existing)
    assert_equal [ "dest" ], @destination.writes
    assert_equal({ "dest" => "GOOD" }, @destination.objects)
    assert_equal "KEEP", @source.objects.fetch("unclassified")
  end

  test "same length different content fails and never overwrites" do
    @destination.objects["dest"] = "EVIL"
    assert_equal 1, transfer.fetch(:failed)
    assert_equal "EVIL", @destination.objects.fetch("dest")
    assert_empty @destination.writes
  end

  test "source corruption fails before any write" do
    @source.objects["owned"] = "EVIL"
    assert_equal 1, transfer.fetch(:failed)
    assert_empty @destination.writes
  end

  test "oversized source and missing required object fail" do
    @source.objects["owned"] = "TOO LONG"
    assert_equal 1, transfer.fetch(:failed)
    @source.objects.delete("owned")
    assert_equal 1, transfer.fetch(:failed)
    assert_empty @destination.writes
  end

  test "invalid ownership manifest and duplicate destinations fail closed" do
    @manifest["brand"] = "hookus"
    assert_raises(Migration::ManifestMediaTransfer::InvalidManifest) { transfer }
    @manifest["brand"] = "date9ja"
    @manifest["objects"] << @manifest["objects"].first.deep_dup
    assert_raises(Migration::ManifestMediaTransfer::InvalidManifest) { transfer }
    assert_empty @destination.writes
  end

  test "CLI exits nonzero when a required object fails" do
    Tempfile.create([ "date9ja-manifest", ".json" ]) do |manifest|
      manifest.write(JSON.generate(@manifest))
      manifest.flush
      Tempfile.create([ "date9ja-fake-s3", ".rb" ]) do |loader|
        loader.write(<<~RUBY)
          require "aws-sdk-s3"
          class MissingRequiredObjectClient
            def head_object(**)
              raise Aws::S3::Errors::NotFound.new(nil, "missing")
            end
            def get_object(**)
              raise Aws::S3::Errors::NoSuchKey.new(nil, "missing")
            end
          end
          Aws::S3::Client.define_singleton_method(:new) { |**| MissingRequiredObjectClient.new }
        RUBY
        loader.flush
        env = %w[CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY
          CLOUDFLARE_R2_BUCKET R2_ENDPOINT ACCESS_KEY_ID SECRET_ACCESS_KEY STAGING_R2_BUCKET].index_with { "synthetic" }
        env.merge!("DATE9JA_MEDIA_MANIFEST" => manifest.path, "RUBYOPT" => "-r#{loader.path}")
        output, status = Open3.capture2e(env, RbConfig.ruby, Rails.root.join("scripts/date9ja/transfer_media_bytes.rb").to_s)
        assert_equal 1, status.exitstatus
        assert_equal 1, JSON.parse(output).fetch("failed")
        assert_equal 0, JSON.parse(output).fetch("transferred")
      end
    end
  end

  test "CLI exits nonzero without an explicit manifest and never lists buckets" do
    output, status = Open3.capture2e({ "DATE9JA_MEDIA_MANIFEST" => nil }, RbConfig.ruby,
      Rails.root.join("scripts/date9ja/transfer_media_bytes.rb").to_s)
    assert_not status.success?
    assert_includes output, "aborted"
    assert_not_includes output, "ACCESS_KEY"
  end
end
