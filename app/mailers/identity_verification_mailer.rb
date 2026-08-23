class IdentityVerificationMailer < ApplicationMailer
  VERIFICATION_TEMPLATES = {
    "dateza" => "dateza_verification_code"
  }.freeze

  def verification_code
    @brand_name = params.fetch(:brand_name)
    @code = params.fetch(:code)
    @heading = "Verify your email"
    @instruction = "Use this code to verify your #{@brand_name} account."
    @preheader = "Your #{@brand_name} verification code expires in 10 minutes."

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: "Verify your #{@brand_name} email",
      template_name: VERIFICATION_TEMPLATES.fetch(params[:brand_slug], "verification_code")
    )
  end

  def email_change_code
    @brand_name = params.fetch(:brand_name)
    @code = params.fetch(:code)
    @heading = "Confirm your new email"
    @instruction = "Use this code to confirm your new #{@brand_name} email address."
    @preheader = "Your #{@brand_name} email change code expires in 10 minutes."

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: "Confirm your new #{@brand_name} email",
      template_name: VERIFICATION_TEMPLATES.fetch(params[:brand_slug], "email_change_code")
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
