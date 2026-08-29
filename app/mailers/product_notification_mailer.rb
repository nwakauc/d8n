class ProductNotificationMailer < ApplicationMailer
  # Keyed by the specific notification_type, not brand_slug: a brand can have
  # many notification types (welcome, like_received, match_created, ...), and
  # only "dateza.welcome" has a bespoke branded template today. Keying this by
  # brand alone would render the "Welcome to DateZA" template — literal H1 text
  # included — for every DateZA product email regardless of what it's actually
  # about. Anything not listed falls back to the generic, type-agnostic
  # welcome.html.erb/welcome.text.erb, which render only @title/@body.
  TEMPLATES = {
    "dateza.welcome" => "dateza_welcome",
    "dateza.like_received" => "dateza_product",
    "dateza.match_created" => "dateza_product",
    "dateza.opener_received" => "dateza_product",
    "dateza.message_received" => "dateza_product"
  }.freeze

  def welcome
    notification = Notification.find_by(id: params[:notification_id])
    presentation = Notifications::EmailPresentation.call(
      notification:,
      notification_type: params.fetch(:notification_type),
      brand_slug: params.fetch(:brand_slug)
    )
    @title = presentation.title
    @body = presentation.body
    @preheader = presentation.preheader
    @actor_name = presentation.actor_name
    @actor_image_url = presentation.actor_image_url
    @preview = presentation.preview
    @cta_label = presentation.cta_label
    @cta_url = presentation.cta_url

    mail(
      from: params.fetch(:from_address),
      to: params.fetch(:recipient),
      subject: presentation.subject,
      template_name: TEMPLATES.fetch(params.fetch(:notification_type), "welcome")
    )
  end
end
