module Api
  class SessionsController < ApplicationController
    # Log in: username + password -> a bearer token good for Session::TOKEN_TTL.
    def create
      user = User.find_by(username: params[:username].to_s.strip)

      unless user&.authenticate(params[:password].to_s)
        return render json: { ok: false, error: "Incorrect username or password." }, status: :unauthorized
      end

      unless user.approved?
        return render json: { ok: false, error: "Your account is not yet approved by an admin." }, status: :forbidden
      end

      session = user.sessions.create!
      render json: { ok: true, token: session.raw_token, user: user_json(user) }
    end

    # Log out: revokes the presented token server-side.
    def destroy
      current_session&.destroy
      render json: { ok: true }
    end
  end
end
