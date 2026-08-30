module Admin
  # Promotes an EXISTING D8N identity to admin (AdminUser + AdminAssignment)
  # across every active brand, using only the current brand-scoped
  # authorization model (Admin::ModeratorContext, ADR 0013). It deliberately
  # does not create a new identity/password:
  #
  # - Identity::RecoveryRequester only issues a reset code for an identifier
  #   that is already *verified* and already has an active password
  #   Credential — it cannot bootstrap a brand-new account.
  # - Identity::PasswordRegistration refuses to register a second time over
  #   an IdentityIdentifier that already exists (see its `register` method) —
  #   so pre-creating a passwordless IdentityIdentifier here would permanently
  #   block that same email from ever self-registering through the normal API.
  #
  # There is therefore no supported path to originate a working, credentialed
  # identity from an offline operator command without either inventing a
  # parallel admin-auth/password mechanism (explicitly out of scope) or
  # emailing an activation link through net-new machinery this ticket does
  # not build. The safe behavior is: only ever promote an identity that
  # already completed normal registration; fail clearly otherwise, so the
  # operator is told to register the account first and rerun.
  class FounderBootstrap
    class MissingEmail < StandardError; end
    class InvalidEmail < StandardError; end
    class IdentityNotFound < StandardError; end
    class RoleMissing < StandardError; end
    class NoActiveBrands < StandardError; end

    ROLE_NAME = "founder".freeze

    Result = Data.define(:user, :admin_user, :admin_role, :assignments)

    def self.call(email:)
      new(email:).call
    end

    def initialize(email:)
      @email_input = email
    end

    def call
      raise MissingEmail, "FOUNDER_EMAIL is required" if email_input.blank?

      login_identifier = Identity::LoginIdentifier.call(email_input)
      unless login_identifier && login_identifier.kind == :email
        raise InvalidEmail, "FOUNDER_EMAIL #{email_input.inspect} is not a valid email address"
      end

      user = existing_user(login_identifier)
      active_brands = Brand.kept.active.to_a
      raise NoActiveBrands, "No active brands exist to assign the founder to" if active_brands.empty?

      role = AdminRole.kept.find_by(name: ROLE_NAME)
      if role.blank?
        raise RoleMissing, "Expected the #{ROLE_NAME.inspect} AdminRole to already be seeded (bin/rails db:seed)"
      end

      admin_user = nil
      assignments = []

      ActiveRecord::Base.transaction do
        admin_user = AdminUser.find_or_initialize_by(user:)
        admin_user.deleted_at = nil
        admin_user.status = :active
        admin_user.save!

        assignments = active_brands.map { |brand| assign!(user:, admin_user:, brand:, role:) }
      end

      Result.new(user:, admin_user:, admin_role: role, assignments:)
    end

    private

    attr_reader :email_input

    def existing_user(login_identifier)
      identity_identifier = IdentityIdentifier.kept.find_by(
        kind: :email, normalized_value: login_identifier.normalized_value
      )
      user = identity_identifier&.user
      if user.blank? || user.deleted_at.present?
        raise IdentityNotFound,
          "No existing D8N identity for #{login_identifier.normalized_value.inspect}. " \
          "Register a normal account with this email through the app first, then rerun this task."
      end

      user
    end

    # A BrandMembership is required for this identity to actually sign in on a
    # given brand's host at all (Identity::PasswordLogin, ADR 0013) — an
    # AdminAssignment without one would be unreachable. Only created if
    # missing; an existing membership's status is left untouched so this task
    # never silently reinstates access on a brand the founder had left.
    def assign!(user:, admin_user:, brand:, role:)
      BrandMembership.kept.find_or_create_by!(user:, brand:) { |membership| membership.status = :active }

      current_assignments = AdminAssignment.kept.where(admin_user:, brand:).to_a
      founder_assignment = current_assignments.find { |assignment| assignment.admin_role_id == role.id }

      current_assignments.each do |assignment|
        next if assignment == founder_assignment

        assignment.update!(status: :revoked, deleted_at: Time.current)
      end

      founder_assignment ||= AdminAssignment.new(admin_user:, brand:, admin_role: role)
      founder_assignment.assign_attributes(status: :active, deleted_at: nil)
      founder_assignment.save!
      founder_assignment
    end
  end
end
