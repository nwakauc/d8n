# frozen_string_literal: true

# Date9ja → D8N — operator-only bcrypt compatibility proof.
#
# Implements SNAPSHOT-RUNBOOK.md §6c. Proves that a legacy Date9ja
# `users.encrypted_password` bcrypt digest authenticates through the REAL D8N
# password path (`Identity::PasswordEngine` / `Identity::PasswordLogin`) with no
# rehash, no truncation, no reset, and that the stored hash stays byte-identical
# to the source digest.
#
# SAFETY CONTRACT
#   - This file contains NO real email, password, bcrypt digest, identifier, or
#     secret. Every sensitive value is read at runtime from an operator-owned,
#     uncommitted manifest pointed to by BCRYPT_PROOF_MANIFEST.
#   - Output is limited to `<prefix_family> <cost> PASS` or
#     `<prefix_family> <cost> FAIL <reason>`. Plaintext, digests, salts, emails
#     and exception text carrying them are scrubbed before anything is printed.
#   - Runs only under RAILS_ENV=test, against a throwaway database. Every bucket
#     is provisioned inside a transaction that is rolled back — nothing persists.
#   - Never calls PasswordEngine.set! (which would rehash). The digest is copied
#     verbatim into credential_password_hashes.password_hash.
#
# Operator command:
#   BCRYPT_PROOF_MANIFEST=/absolute/path/to/manifest.tsv \
#     bin/rails runner -e test scripts/date9ja/bcrypt_proof.rb

module Date9ja
  module BcryptProof
    BRAND_SLUG = "date9ja"
    AUTH_METHODS = %w[email_password phone_password].freeze
    THROWAWAY_DATABASE = "d8n_test"
    LOCAL_DATABASE_HOSTS = [ nil, "", "localhost", "127.0.0.1", "::1" ].freeze

    # 60-char bcrypt: $2<a|b|x|y>$<2-digit cost>$<22-char salt + 31-char digest>.
    DIGEST_RE = %r{\A\$2[abxy]\$(\d{2})\$[./A-Za-z0-9]{53}\z}
    COLUMNS = %i[prefix_family cost email password bcrypt_digest].freeze

    Row = Data.define(:prefix_family, :cost, :email, :password, :digest)

    class ManifestError < StandardError; end

    module_function

    # Returns a process exit status: 0 all PASS, 1 any FAIL, 2 manifest error,
    # 3 wrong environment.
    def run(manifest_path:, out: $stdout, err: $stderr)
      unless defined?(Rails) && Rails.env.test?
        err.puts "refusing to run outside RAILS_ENV=test (throwaway database only)"
        return 3
      end
      unless throwaway_database?
        err.puts "refusing to run unless the test database is the local d8n_test throwaway database"
        return 3
      end

      rows = parse_manifest(manifest_path, err:)
      secrets = collect_secrets(rows)

      failed = false
      rows.each do |row|
        outcome =
          begin
            verify_bucket(row)
          rescue StandardError => e
            "FAIL setup (#{scrub(e.class.name, secrets)})"
          end
        failed ||= outcome != :pass
        label = "#{row.prefix_family} #{row.cost}"
        out.puts(outcome == :pass ? "#{label} PASS" : "#{label} #{scrub(outcome, secrets)}")
      end

      failed ? 1 : 0
    rescue ManifestError => e
      err.puts "manifest: #{scrub(e.message, collect_secrets(nil))}"
      2
    end

    def main
      status = run(manifest_path: ENV["BCRYPT_PROOF_MANIFEST"].to_s)
      exit status
    end

    # ---- manifest -----------------------------------------------------------

    def parse_manifest(path, err: $stderr)
      raise ManifestError, "BCRYPT_PROOF_MANIFEST is not set" if path.to_s.empty?
      raise ManifestError, "BCRYPT_PROOF_MANIFEST must be an absolute path" unless File.absolute_path?(path)
      raise ManifestError, "manifest not found at the given path" unless File.file?(path)

      warn_on_permissions(path, err:)

      rows = []
      seen = {}
      File.open(path, "r:BOM|UTF-8") do |file|
        file.each_line.with_index(1) do |line, lineno|
          line = line.chomp
          next if line.strip.empty? || line.lstrip.start_with?("#")

          fields = line.split("\t", -1)
          # Tolerate the documented header row.
          next if lineno_is_header?(fields)

          row = build_row(fields, lineno)
          bucket = [ row.prefix_family, row.cost ]
          if seen[bucket]
            raise ManifestError, "duplicate bucket #{row.prefix_family} #{row.cost} (lines #{seen[bucket]} and #{lineno})"
          end

          seen[bucket] = lineno
          rows << row
        end
      end

      raise ManifestError, "manifest contains no bucket rows" if rows.empty?

      rows
    rescue ArgumentError
      raise ManifestError, "manifest must be valid UTF-8"
    end

    def lineno_is_header?(fields)
      fields.map { |f| f.strip.downcase } == COLUMNS.map(&:to_s)
    end

    def build_row(fields, lineno)
      unless fields.length == COLUMNS.length
        raise ManifestError, "line #{lineno}: expected #{COLUMNS.length} tab-separated fields, got #{fields.length}"
      end

      values = COLUMNS.zip(fields.each_with_index.map { |value, index| index == 3 ? value : value.strip }).to_h
      values.each do |key, value|
        raise ManifestError, "line #{lineno}: missing #{key}" if value.empty?
      end

      digest = values[:bcrypt_digest]
      match = DIGEST_RE.match(digest)
      raise ManifestError, "line #{lineno}: bcrypt_digest is not a well-formed 60-char bcrypt hash" unless match

      unless values[:prefix_family] == digest[0, 4]
        raise ManifestError, "line #{lineno}: prefix_family does not match the digest prefix"
      end

      cost = values[:cost]
      raise ManifestError, "line #{lineno}: cost must be two digits" unless cost.match?(/\A\d{2}\z/)
      raise ManifestError, "line #{lineno}: cost must be between 04 and 31" unless cost.to_i.between?(4, 31)
      raise ManifestError, "line #{lineno}: cost does not match the digest cost" unless cost == match[1]

      Row.new(
        prefix_family: values[:prefix_family],
        cost: cost,
        email: values[:email],
        password: values[:password],
        digest: digest
      )
    end

    def warn_on_permissions(path, err:)
      mode = File.stat(path).mode
      err.puts "warning: manifest is group/other-accessible (mode #{format('%o', mode & 0o777)})" if (mode & 0o077).nonzero?
    rescue StandardError
      # Non-fatal; permission bits are advisory on some filesystems.
    end

    # ---- verification ------------------------------------------------------

    # Provisions one bucket entirely inside a rolled-back transaction and returns
    # :pass or a "FAIL <reason>" string.
    def verify_bucket(row)
      outcome = nil

      with_sensitive_logging_suppressed do
        ActiveRecord::Base.transaction do
          brand = provision_brand
          user = User.create!
          identifier = IdentityIdentifier.create!(
            user: user, kind: :email, normalized_value: row.email, verified_at: Time.current
          )
          credential = Credential.create!(
            user: user, identity_identifier: identifier, kind: :password, status: :active
          )
          # Verbatim copy — deliberately NOT PasswordEngine.set!.
          CredentialPasswordHash.create!(
            credential: credential,
            credential_kind: Credential.kinds.fetch("password"),
            password_hash: row.digest,
            password_changed_at: Time.current
          )
          BrandMembership.create!(user: user, brand: brand, status: :active)

          outcome = evaluate(row, brand, credential)
          raise ActiveRecord::Rollback
        end
      end

      outcome
    end

    def evaluate(row, brand, credential)
      unless Identity::PasswordEngine.matches?(credential: credential, password: row.password) == true
        return "FAIL verify"
      end

      unless Identity::PasswordEngine.matches?(credential: credential, password: wrong_password(row.password)) == false
        return "FAIL wrong-password"
      end

      login = Identity::PasswordLogin.call(
        brand: brand,
        identifier: row.email,
        password: row.password,
        device_name: "bcrypt-proof",
        user_agent: "bcrypt-proof"
      )
      return "FAIL login" unless login.success? && login.session.present?
      persisted_session = Session.find_by(id: login.session.id)
      return "FAIL session" unless persisted_session&.user_id == credential.user_id &&
        persisted_session.brand_id == brand.id && persisted_session.credential_id == credential.id

      stored = CredentialPasswordHash.find(credential.id).password_hash
      return "FAIL hash-mutated" unless stored.b == row.digest.b

      :pass
    end

    # Deterministic wrong password that differs in the FIRST byte, so bcrypt's
    # 72-byte truncation can never make it collide with the real password.
    def wrong_password(password)
      first = password[0] == "a" ? "b" : "a"
      "#{first}#{password[1..]}"
    end

    def provision_brand
      brand = Brand.kept.find_or_initialize_by(slug: BRAND_SLUG)
      brand.assign_attributes(name: "Date9ja", status: :active, auth_methods: AUTH_METHODS)
      brand.save! if brand.new_record? || brand.changed?
      brand
    end

    def throwaway_database?
      return false if ENV["DATABASE_URL"].to_s != ""

      config = ActiveRecord::Base.connection_db_config
      database = config.database.to_s
      host = config.configuration_hash[:host]
      # Minitest parallelization suffixes the per-worker database (`d8n_test_3`).
      database.match?(/\A#{Regexp.escape(THROWAWAY_DATABASE)}(?:[-_]\d+)?\z/) &&
        LOCAL_DATABASE_HOSTS.include?(host)
    rescue StandardError
      false
    end

    def with_sensitive_logging_suppressed
      loggers = [ Rails.logger, ActiveRecord::Base.logger ].compact.uniq.select { |logger| logger.respond_to?(:level=) }
      levels = loggers.to_h { |logger| [ logger, logger.level ] }
      loggers.each { |logger| logger.level = Logger::FATAL }
      yield
    ensure
      levels&.each { |logger, level| logger.level = level }
    end

    # ---- scrubbing --------------------------------------------------------

    def collect_secrets(rows)
      return [] if rows.nil?

      rows.flat_map { |r| [ r.password, r.digest, r.email ] }
        .compact
        .reject(&:empty?)
        .uniq
        .sort_by { |s| -s.length }
    end

    def scrub(text, secrets)
      result = text.to_s
      secrets.each { |secret| result = result.gsub(secret, "[redacted]") }
      # Belt and braces: redact anything shaped like a bcrypt digest.
      result.gsub(%r{\$2[abxy]\$\d{2}\$[./A-Za-z0-9]{53}}, "[redacted-digest]")
    end
  end
end

Date9ja::BcryptProof.main unless ENV["BCRYPT_PROOF_NO_AUTORUN"] == "1"
