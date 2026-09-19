# Layered bot protection for signup (see User model / RegistrationsController
# for the other two layers: the quiz-question gate and the 24h pending-expiry
# sweep). This throttles by IP so a scripted loop can't claim large swaths of
# the 4-digit user_id space.
class Rack::Attack
  throttle("registrations/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/api/registrations" && req.post?
  end

  self.throttled_responder = lambda do |_request|
    body = { ok: false, error: "Too many registration attempts — please try again later." }.to_json
    [ 429, { "Content-Type" => "application/json" }, [ body ] ]
  end
end

Rails.application.config.middleware.use Rack::Attack
