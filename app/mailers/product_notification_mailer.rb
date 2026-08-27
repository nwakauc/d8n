class ProductNotificationMailer < ApplicationMailer
  # Keyed by the specific notification_type, not brand_slug: a brand can have
  # many notification types (welcome, like_received, match_created, ...), and
  # only "dateza.welcome" has a bespoke branded template today. Keying this by
  # brand alone would render the "Welcome to DateZA" template — literal H1 text
  # included — for every DateZA product email regardless of what it's actually
  # about. Anything not listed falls back to the generic, type-agnostic
  # welcome.html.erb/welcome.text.erb, which render only @title/@body.
  TEMPLATES = {
    "dateza.welcome" => "dateza_welcome"
  }.freeze

  def welcome
    definition = Notifications::Types.fetch(params.fetch(:notification_type))
    @title = definition.title
    @body = definition.body

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: definition.email_subject,
      template_name: TEMPLATES.fetch(params.fetch(:notification_type), "welcome")
    )
  end
end
