class IdentityVerificationMailer < ApplicationMailer
  VERIFICATION_TEMPLATES = {
    "dateza" => "dateza_verification_code"
  }.freeze

  def verification_code
    @brand_name = params.fetch(:brand_name)
    @code = params.fetch(:code)

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: "Verify your #{@brand_name} email",
      template_name: VERIFICATION_TEMPLATES.fetch(params[:brand_slug], "verification_code")
    )
  end

  def recovery_code
    @brand_name = params.fetch(:brand_name)
    @code = params.fetch(:code)

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: "Reset your #{@brand_name} password"
    )
  end
end
