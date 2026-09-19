# Mirrors app.rb's permissive CORS (Access-Control-Allow-Origin: *). Safe here
# because auth uses a bearer token, not cookies, so wildcard origins don't
# carry the usual CSRF/credential-leak risk of cookie-based auth.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/api/*",
      headers: :any,
      methods: [ :get, :post, :patch, :delete, :options ]
  end
end
