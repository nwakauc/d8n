module Notifications
  class EmailPresentation
    Result = Data.define(
      :subject, :title, :body, :preheader, :actor_name, :actor_image_url,
      :preview, :cta_label, :cta_url
    )

    PRESENTERS = {
      "dateza" => Notifications::EmailPresenters::Dateza
    }.freeze

    def self.call(notification:, notification_type:, brand_slug:)
      presenter = PRESENTERS[brand_slug]
      return presenter.call(notification:) if presenter && notification

      definition = Types.fetch(notification_type)
      Result.new(
        subject: definition.email_subject,
        title: definition.title,
        body: definition.body,
        preheader: definition.body,
        actor_name: nil,
        actor_image_url: nil,
        preview: nil,
        cta_label: nil,
        cta_url: nil
      )
    end
  end
end
