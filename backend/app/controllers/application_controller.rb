class ApplicationController < ActionController::API
  rescue_from ActiveRecord::StatementInvalid do |e|
    if e.cause.is_a?(SQLite3::Exception)
      render json: { ok: false, error: "Database is locked by another process." }, status: :service_unavailable
    else
      raise e
    end
  end

  private

  def require_param!(value, message)
    render(json: { ok: false, error: message }, status: :bad_request) and return false if value.to_s.strip.empty?
    true
  end
end
