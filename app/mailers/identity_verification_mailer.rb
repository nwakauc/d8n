class IdentityVerificationMailer < ApplicationMailer
  def verification_code
    @brand_name = params.fetch(:brand_name)
    @code = params.fetch(:code)

    mail(to: params.fetch(:recipient), subject: "Verify your #{@brand_name} email")
  end
end
