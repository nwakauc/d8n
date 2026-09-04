# frozen_string_literal: true

module Date9ja
  module Import
    # Exercises the full signed-out authentication journey of an ALREADY-MIGRATED
    # Date9ja account against the real shared D8N Identity services — nothing here
    # is Date9ja-specific infrastructure, it only drives the platform primitives
    # the way the web/mobile clients will:
    #
    #   PasswordLogin · Session (brand-scoped) · SessionAuthenticator (isolation)
    #   RecoveryRequester → RecoveryVerifier → PasswordReset (session revocation)
    #   Accounts::DeactivateAccount ↔ Identity::AccountReactivation
    #
    # It is the broad companion to `scripts/date9ja/bcrypt_proof.rb` (which proves
    # ONLY the raw digest verifies): this proves the migrated account shape works
    # end to end. Used by the L1 synthetic rehearsal and by the operator
    # `date9ja:verify_auth_transition` rake task (rolled-back, PII-free).
    #
    # `to_h` is deterministic and PII-free: aggregate pass/fail counts per check
    # and a distinct list of `{check, reason}` pairs — never an email, phone,
    # digest, code, token, or free text.
    class AuthTransitionCheck
      LIFECYCLES = %i[active suspended recovery_required].freeze

      CHECKS = %i[
        lifecycle_supported
        resolve
        login_ok
        wrong_password_rejected
        legacy_hash_preserved
        session_brand_scoped
        cross_brand_rejected
        logout_revokes_session
        login_blocked
        no_residual_session
        recovery_unavailable_fails_closed
        reactivation_roundtrip
        recovery_roundtrip
        recovery_revokes_sessions
        old_password_rejected
        recovered_password_logs_in
      ].freeze

      # One migrated account under test. `identifier`/`password` are the member's
      # real sign-in inputs; `digest` is the exact bcrypt string the importer
      # stored (nil for a recovery-required account); `lifecycle` is the expected
      # post-import membership state. `recovery_expected` is false when the
      # account owns no verified recovery channel (unverified email, no verified
      # phone) — signed-out recovery is then legitimately unavailable (ADR 0012)
      # and the check asserts it fails closed rather than delivering a code.
      Subject = Data.define(:source_ref, :identifier, :password, :digest, :lifecycle, :recovery_expected) do
        def self.build(source_ref:, identifier:, lifecycle:, password: nil, digest: nil, recovery_expected: true)
          new(source_ref:, identifier:, password:, digest:, lifecycle:, recovery_expected:)
        end
      end

      Result = Data.define(:reconciliation) do
        def all_passed? = reconciliation.all_passed?
      end

      class ManifestError < StandardError; end

      # Parses the operator manifest (TSV lines:
      # `identifier<TAB>password<TAB>lifecycle[<TAB>no_recovery]`, `#` comments and
      # blank lines ignored) into Subjects. Fails closed on an empty manifest or
      # an unknown lifecycle — the error names the line and the bad token only,
      # never an identifier or password.
      def self.parse_manifest(lines)
        subjects = []
        lines.each_with_index do |line, idx|
          text = line.to_s.chomp
          next if text.strip.empty? || text.lstrip.start_with?("#")

          identifier, password, lifecycle_raw, recovery = text.split("\t", -1)
          lifecycle = lifecycle_raw.to_s.strip.to_sym
          unless LIFECYCLES.include?(lifecycle)
            raise ManifestError,
              "line #{idx + 1}: unknown lifecycle #{lifecycle.inspect} (allowed: #{LIFECYCLES.join(', ')})"
          end

          subjects << Subject.build(
            source_ref: nil, identifier: identifier.to_s.strip,
            password: password.to_s.empty? ? nil : password,
            lifecycle:, recovery_expected: recovery.to_s.strip != "no_recovery"
          )
        end
        raise ManifestError, "manifest contains no subject rows" if subjects.empty?

        subjects
      end

      def self.call(...) = new(...).call

      # `isolation_brand` is any other active brand; used only to assert a
      # date9ja session cannot authenticate elsewhere. When absent that single
      # check is skipped (recorded, not failed).
      def initialize(brand:, subjects:, isolation_brand: nil, new_password: "recovered-passphrase-9ja")
        @brand = brand
        @subjects = subjects
        @isolation_brand = isolation_brand
        @new_password = new_password
        @tally = Tally.new
      end

      def call
        @subjects.each do |subject|
          @tally.subject(subject.lifecycle)
          run_subject(subject)
        end
        Result.new(@tally)
      end

      private

      attr_reader :brand, :isolation_brand, :new_password

      def run_subject(subject)
        unless LIFECYCLES.include?(subject.lifecycle)
          return record(:lifecycle_supported, :fail, "unknown_lifecycle")
        end
        record(:lifecycle_supported, :pass)

        resolved = resolve(subject)
        return unless resolved

        case subject.lifecycle
        when :active then run_active(subject, resolved)
        when :recovery_required then run_recovery_required(subject, resolved)
        when :suspended then run_suspended(subject, resolved)
        end
      end

      # --- resolution --------------------------------------------------------

      Resolved = Data.define(:identity_identifier, :user, :credential)

      def resolve(subject)
        parsed = ::Identity::LoginIdentifier.call(subject.identifier, brand:)
        return record(:resolve, :fail, "identifier_unparseable") if parsed.blank?

        matches = IdentityIdentifier.kept.where(kind: parsed.kind, normalized_value: parsed.lookup_values).limit(2).to_a
        ii = matches.one? ? matches.first : nil
        return record(:resolve, :fail, "identity_not_found") if ii.blank?

        user = ii.user
        credential = ii.credentials.kept.find_by(kind: :password)
        return record(:resolve, :fail, "password_credential_missing") if credential.blank?

        record(:resolve, :pass)
        Resolved.new(identity_identifier: ii, user:, credential:)
      end

      # --- active account ---------------------------------------------------

      def run_active(subject, identity)
        login = login_as(subject.identifier, subject.password)
        if login.success? && persisted_session?(login, identity)
          record(:login_ok, :pass)
        else
          record(:login_ok, :fail, login.error.to_s.presence || "no_session")
        end

        wrong = login_as(subject.identifier, mutate(subject.password))
        assert(:wrong_password_rejected, !wrong.success? && wrong.error == :invalid_credentials)

        assert(:legacy_hash_preserved, legacy_hash_intact?(identity.credential, subject.digest))

        assert(:session_brand_scoped, login.success? && login.session&.brand_id == brand.id)
        check_cross_brand(login)
        check_logout(login)

        reactivation_roundtrip(subject, identity)
        if subject.recovery_expected
          recovery_roundtrip(subject, identity)
        else
          recovery_unavailable(subject, identity)
        end
      end

      # An account with no verified channel: signed-out recovery must fail closed
      # (ADR 0012) — no usable code is delivered — while the password still works.
      def recovery_unavailable(subject, identity)
        ::Identity::RecoveryRequester.call(brand:, identifier: subject.identifier)
        code = delivered_recovery_code(identity.identity_identifier)
        assert(:recovery_unavailable_fails_closed, code.blank?)
        still_in = login_as(subject.identifier, subject.password)
        assert(:recovered_password_logs_in, still_in.success?)
      end

      def check_cross_brand(login)
        return record(:cross_brand_rejected, :skip, "no_isolation_brand") if isolation_brand.blank?
        return record(:cross_brand_rejected, :fail, "no_token") unless login.success? && login.raw_token

        other = ::Identity::SessionAuthenticator.call(brand: isolation_brand, token: login.raw_token)
        assert(:cross_brand_rejected, !other.success? && other.error == :wrong_brand)
      end

      # Sign-out parity: revoking the session makes the token unauthenticable
      # (Date9ja `sign_out` = JWT revoke; D8N = session revoke).
      def check_logout(login)
        return record(:logout_revokes_session, :fail, "no_session") unless login.success? && login.session

        ::Identity::SessionRevoker.call(session: login.session)
        after = ::Identity::SessionAuthenticator.call(brand:, token: login.raw_token)
        assert(:logout_revokes_session, !after.success? && after.error == :revoked_session)
      end

      # --- recovery-required account ---------------------------------------

      def run_recovery_required(subject, identity)
        blocked = login_as(subject.identifier, subject.password || "any-guess-whatsoever")
        assert(:login_blocked, !blocked.success? && blocked.error == :invalid_credentials)

        recovery_roundtrip(subject, identity, expect_prior_password: false)
      end

      # --- suspended account ---------------------------------------------

      def run_suspended(subject, identity)
        attempt = login_as(subject.identifier, subject.password)
        assert(:login_blocked, !attempt.success? && attempt.error == :invalid_credentials)
        assert(:no_residual_session, !Session.active.exists?(user: identity.user, brand:))
      end

      # --- shared journeys ---------------------------------------------

      def reactivation_roundtrip(subject, identity)
        Accounts::DeactivateAccount.call(user: identity.user, brand:)

        deactivated_login = login_as(subject.identifier, subject.password)
        unless !deactivated_login.success? && deactivated_login.error == :account_deactivated
          return record(:reactivation_roundtrip, :fail, "not_reported_deactivated")
        end

        reactivated = ::Identity::AccountReactivation.call(
          brand:, identifier: subject.identifier, password: subject.password
        )
        ok = reactivated.success? && reactivated.session.present? &&
          BrandMembership.kept.active.exists?(user: identity.user, brand:)
        record(:reactivation_roundtrip, ok ? :pass : :fail, ok ? nil : "reactivation_failed")
      end

      def recovery_roundtrip(subject, identity, expect_prior_password: true)
        pre_sessions = issue_probe_session(identity) if expect_prior_password

        request = ::Identity::RecoveryRequester.call(brand:, identifier: subject.identifier)
        code = delivered_recovery_code(identity.identity_identifier)
        unless request.success? && code
          return record(:recovery_roundtrip, :fail, code ? "requester_unsuccessful" : "code_not_delivered")
        end

        verify = ::Identity::RecoveryVerifier.call(brand:, identifier: subject.identifier, code:)
        return record(:recovery_roundtrip, :fail, "verify_#{verify.error}") unless verify.success? && verify.reset_token

        reset = ::Identity::PasswordReset.call(
          brand:, reset_token: verify.reset_token,
          password: new_password, password_confirmation: new_password
        )
        return record(:recovery_roundtrip, :fail, "reset_#{reset.error}") unless reset.success?

        record(:recovery_roundtrip, :pass)

        if expect_prior_password
          assert(:recovery_revokes_sessions, reset.revoked_session_count.positive? && revoked?(pre_sessions))
          old = login_as(subject.identifier, subject.password)
          assert(:old_password_rejected, !old.success?)
        end

        recovered = login_as(subject.identifier, new_password)
        assert(:recovered_password_logs_in, recovered.success? && recovered.session.present?)
      end

      # --- primitives -------------------------------------------------

      def login_as(identifier, password)
        ::Identity::PasswordLogin.call(
          brand:, identifier:, password: password.to_s,
          device_name: "auth-transition-check", user_agent: "auth-transition-check"
        )
      end

      def issue_probe_session(identity)
        _raw, session = Session.issue!(user: identity.user, brand:, credential: identity.credential)
        session
      end

      def revoked?(session)
        session.blank? || session.reload.revoked?
      end

      def persisted_session?(login, identity)
        s = login.session && Session.find_by(id: login.session.id)
        s.present? && s.user_id == identity.user.id && s.brand_id == brand.id &&
          s.credential_id == identity.credential.id
      end

      def legacy_hash_intact?(credential, digest)
        return true if digest.blank? # recovery-required: nothing to preserve

        stored = CredentialPasswordHash.find_by(credential_id: credential.id)&.password_hash
        stored.present? && stored.b == digest.b
      end

      def delivered_recovery_code(identity_identifier)
        OtpChallenge.where(brand:, identity_identifier:, kind: "password_recovery")
          .order(created_at: :desc).first&.delivery_code.presence
      end

      # A deterministic wrong password differing in the FIRST byte, so bcrypt's
      # 72-byte truncation can never make it collide with the real one.
      def mutate(password)
        password = password.to_s
        first = password[0] == "a" ? "b" : "a"
        "#{first}#{password[1..]}"
      end

      def assert(check, condition)
        record(check, condition ? :pass : :fail, condition ? nil : "assertion_failed")
      end

      def record(check, outcome, reason = nil)
        raise ArgumentError, "unknown check #{check}" unless CHECKS.include?(check)

        @tally.check(check, outcome, reason)
        nil
      end

      # Deterministic PII-free tally.
      class Tally
        OUTCOMES = %i[pass fail skip].freeze

        def initialize
          @subjects = 0
          @lifecycles = Hash.new(0)
          @checks = Hash.new { |h, k| h[k] = Hash.new(0) }
          @failure_reasons = Hash.new(0)
        end

        def subject(lifecycle)
          @subjects += 1
          @lifecycles[lifecycle.to_s] += 1
        end

        def check(name, outcome, reason)
          raise ArgumentError, "unknown outcome #{outcome}" unless OUTCOMES.include?(outcome)

          @checks[name.to_s][outcome.to_s] += 1
          @failure_reasons["#{name}:#{reason}"] += 1 if outcome == :fail && reason
        end

        def failures = @checks.sum { |_, o| o["fail"].to_i }

        # A run with no subjects is not a pass — it verified nothing.
        def all_passed? = @subjects.positive? && failures.zero?

        def to_h
          {
            "subjects_considered" => @subjects,
            "lifecycles" => @lifecycles.sort.to_h,
            "checks" => AuthTransitionCheck::CHECKS.each_with_object({}) do |name, acc|
              counts = @checks[name.to_s]
              acc[name.to_s] = { "pass" => counts["pass"], "fail" => counts["fail"], "skip" => counts["skip"] } if counts.any?
            end,
            "failure_reasons" => @failure_reasons.select { |_, n| n.positive? }.sort.to_h,
            "failures" => failures,
            "all_passed" => all_passed?
          }
        end
      end
    end
  end
end
