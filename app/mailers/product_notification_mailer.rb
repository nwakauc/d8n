class ProductNotificationMailer < ApplicationMailer
  WELCOME_TEMPLATES = {
    "dateza" => "dateza_welcome"
  }.freeze

  def welcome
    definition = Notifications::Types.fetch(params.fetch(:notification_type))
    @title = definition.title
    @body = definition.body

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: definition.email_subject,
      template_name: WELCOME_TEMPLATES.fetch(params[:brand_slug], "welcome")
    )
  end
end
