class ProductNotificationMailer < ApplicationMailer
  def welcome
    definition = Notifications::Types.fetch(params.fetch(:notification_type))
    @title = definition.title
    @body = definition.body

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: definition.email_subject
    )
  end
end
