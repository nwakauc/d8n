require "test_helper"
require "bcrypt"
require "stringio"
require "tmpdir"

# All values here are SYNTHETIC — bcrypt digests generated in-test from throwaway
# passwords. No Date9ja data is involved.
ENV["BCRYPT_PROOF_NO_AUTORUN"] = "1"
require Rails.root.join("scripts/date9ja/bcrypt_proof").to_s

class Date9ja::BcryptProofTest < ActiveSupport::TestCase
  SYNTHETIC_PASSWORD = "correct-horse-battery"

  setup do
    @dir = Dir.mktmpdir("bcrypt-proof-test")
  end

  teardown do
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  test "verifies a legacy-style digest through the real D8N password path" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    out, err, status = run_proof([ row("$2a$", "04", "seed-a04@proof.invalid", SYNTHETIC_PASSWORD, digest) ])

    assert_equal 0, status
    assert_equal "$2a$ 04 PASS", out.strip
    assert_empty err
  end

  test "does not persist any records" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    assert_no_difference [
      -> { User.count }, -> { IdentityIdentifier.count }, -> { Credential.count },
      -> { CredentialPasswordHash.count }, -> { BrandMembership.count }, -> { Session.count },
      -> { AuthAttempt.count }, -> { SecurityEvent.count }
    ] do
      run_proof([ row("$2a$", "04", "seed-noop@proof.invalid", SYNTHETIC_PASSWORD, digest) ])
    end
  end

  test "accepts a password whose meaningful value includes surrounding spaces" do
    password = " leading-and-trailing-spaces "
    digest = BCrypt::Password.create(password, cost: 4).to_s
    out, _err, status = run_proof([ row("$2a$", "04", "seed-spaces@proof.invalid", password, digest) ])

    assert_equal 0, status
    assert_equal "$2a$ 04 PASS", out.strip
  end

  test "reports FAIL verify when the plaintext does not match the digest" do
    digest = BCrypt::Password.create("a-different-password", cost: 4).to_s
    out, _err, status = run_proof([ row("$2a$", "04", "seed-mismatch@proof.invalid", SYNTHETIC_PASSWORD, digest) ])

    assert_equal 1, status
    assert_equal "$2a$ 04 FAIL verify", out.strip
  end

  test "preserves the $2b$ prefix byte-for-byte" do
    raw = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    digest = raw.sub(/\A\$2a\$/, "$2b$")
    out, _err, status = run_proof([ row("$2b$", "04", "seed-b04@proof.invalid", SYNTHETIC_PASSWORD, digest) ])

    assert_equal 0, status
    assert_equal "$2b$ 04 PASS", out.strip
  end

  test "rejects a malformed bcrypt digest without touching the database" do
    out, err, status = run_proof([ row("$2a$", "04", "seed-bad@proof.invalid", SYNTHETIC_PASSWORD, "$2a$04$not-a-real-hash") ])

    assert_equal 2, status
    assert_empty out
    assert_match(/\Amanifest: /, err)
  end

  test "rejects duplicate prefix/cost buckets" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    rows = [
      row("$2a$", "04", "seed-dup1@proof.invalid", SYNTHETIC_PASSWORD, digest),
      row("$2a$", "04", "seed-dup2@proof.invalid", SYNTHETIC_PASSWORD, digest)
    ]
    out, err, status = run_proof(rows)

    assert_equal 2, status
    assert_empty out
    assert_match(/duplicate bucket/, err)
  end

  test "fails closed on a missing field" do
    _out, err, status = run_proof([ [ "$2a$", "04", "", SYNTHETIC_PASSWORD, BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s ].join("\t") ])

    assert_equal 2, status
    assert_match(/missing email/, err)
  end

  test "rejects a prefix or cost that disagrees with the digest" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    _out, err, status = run_proof([ row("$2a$", "12", "seed-costskew@proof.invalid", SYNTHETIC_PASSWORD, digest) ])

    assert_equal 2, status
    assert_match(/cost does not match/, err)
  end

  test "rejects an unsupported bcrypt cost before verification" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    _out, err, status = run_proof([ row("$2a$", "99", "seed-cost-range@proof.invalid", SYNTHETIC_PASSWORD, digest) ])

    assert_equal 2, status
    assert_match(/cost must be between 04 and 31/, err)
  end

  test "rejects a non-absolute manifest path" do
    err = StringIO.new
    status = Date9ja::BcryptProof.run(manifest_path: "relative/manifest.tsv", out: StringIO.new, err: err)
    assert_equal 2, status
    assert_match(/absolute path/, err.string)
  end

  test "refuses a DATABASE_URL override even in the test environment" do
    original = ENV["DATABASE_URL"]
    ENV["DATABASE_URL"] = "postgres://example.invalid/not-d8n-test"
    err = StringIO.new

    status = Date9ja::BcryptProof.run(
      manifest_path: "/tmp/does-not-need-to-exist.tsv", out: StringIO.new, err:
    )

    assert_equal 3, status
    assert_match(/local d8n_test/, err.string)
  ensure
    ENV["DATABASE_URL"] = original
  end

  test "warns when the manifest is group or other accessible" do
    digest = BCrypt::Password.create(SYNTHETIC_PASSWORD, cost: 4).to_s
    path = write_manifest([ row("$2a$", "04", "seed-perm@proof.invalid", SYNTHETIC_PASSWORD, digest) ])
    File.chmod(0o644, path)
    err = StringIO.new
    Date9ja::BcryptProof.run(manifest_path: path, out: StringIO.new, err: err)

    assert_match(/group\/other-accessible/, err.string)
  end

  test "never emits the plaintext, digest, or email" do
    digest = BCrypt::Password.create("yet-another-secret", cost: 4).to_s # mismatch -> FAIL path exercises scrubbing
    email = "seed-scrub@proof.invalid"
    out, err, _status = run_proof([ row("$2a$", "04", email, "yet-another-secret", digest) ])

    [ out, err ].each do |stream|
      assert_not_includes stream, "yet-another-secret"
      assert_not_includes stream, digest
      assert_not_includes stream, email
    end
  end

  test "wrong_password differs in the first byte" do
    assert_equal "b-secret", Date9ja::BcryptProof.wrong_password("a-secret")
    assert_equal "a-secret", Date9ja::BcryptProof.wrong_password("b-secret")
    assert_not_equal "x", Date9ja::BcryptProof.wrong_password("x")
  end

  private

  def row(prefix, cost, email, password, digest)
    [ prefix, cost, email, password, digest ].join("\t")
  end

  def write_manifest(lines)
    path = File.join(@dir, "manifest.tsv")
    File.write(path, ([ "#{Date9ja::BcryptProof::COLUMNS.join("\t")}" ] + lines).join("\n") + "\n")
    File.chmod(0o600, path)
    path
  end

  def run_proof(lines)
    path = write_manifest(lines)
    out = StringIO.new
    err = StringIO.new
    status = Date9ja::BcryptProof.run(manifest_path: path, out: out, err: err)
    [ out.string, err.string, status ]
  end
end
