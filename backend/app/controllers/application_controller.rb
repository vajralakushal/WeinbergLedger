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

  def current_session
    return @current_session if defined?(@current_session)

    @current_session = bearer_token.present? ? Session.authenticate(bearer_token) : nil
  end

  def current_user
    current_session&.user
  end

  def require_login!
    unless current_user
      render json: { ok: false, error: "You must be logged in." }, status: :unauthorized
    end
  end

  def require_admin!
    return require_login! unless current_user

    unless current_user.admin_status
      render json: { ok: false, error: "Admin access required." }, status: :forbidden
    end
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.start_with?("Bearer ") ? header.delete_prefix("Bearer ").strip : nil
  end

  def user_json(user)
    {
      user_id: user.user_id,
      username: user.username,
      first_name: user.first_name,
      last_name: user.last_name,
      admin_status: user.admin_status,
      must_change_password: user.must_change_password
    }
  end
end
