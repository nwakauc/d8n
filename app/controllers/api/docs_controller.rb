class Api::DocsController < ApplicationController
  DOCS_HTML = <<~HTML.freeze
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>D8N API Documentation</title>
        <link rel="stylesheet" href="/api-docs/swagger-ui.css">
      </head>
      <body>
        <div id="swagger-ui"></div>
        <script src="/api-docs/swagger-ui-bundle.js"></script>
        <script src="/api-docs/swagger-initializer.js"></script>
      </body>
    </html>
  HTML

  def show
    response.headers["Cache-Control"] = "public, max-age=300"
    response.headers["Content-Security-Policy"] = content_security_policy
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    render body: DOCS_HTML, content_type: "text/html"
  end

  private

  def content_security_policy
    "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; " \
      "img-src 'self' data:; connect-src 'self'; font-src 'self'; " \
      "base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
  end
end
