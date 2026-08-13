window.addEventListener("load", function () {
  window.ui = SwaggerUIBundle({
    url: "/api/v1/openapi.json",
    dom_id: "#swagger-ui",
    deepLinking: true,
    displayRequestDuration: true,
    docExpansion: "none",
    filter: true,
    persistAuthorization: false,
    tryItOutEnabled: true,
    validatorUrl: null
  });
});
