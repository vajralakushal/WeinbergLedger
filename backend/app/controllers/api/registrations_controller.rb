module Api
  # Public signup. Gated by a trivial quiz question (per spec) as a UX-level
  # bot filter; IP rate limiting (config/initializers/rack_attack.rb) and the
  # 24h pending-expiry sweep do the real work of protecting the 4-digit ID
  # space from being exhausted by scripted signups.
  class RegistrationsController < ApplicationController
    QUIZ_ANSWER = "1"

    before_action :sweep_stale_users!

    def create
      if params[:light_speed].to_s.strip != QUIZ_ANSWER
        return render json: { ok: false, denied: true, error: "Registration has been denied." }, status: :forbidden
      end

      user = User.new(
        first_name: params[:first_name].to_s.strip,
        last_name: params[:last_name].to_s.strip,
        username: params[:username].to_s.strip,
        password: params[:password],
        approval_status: User::PENDING
      )

      if user.save
        render json: { ok: true, user_id: user.user_id, approval_status: user.approval_status }, status: :created
      else
        render json: { ok: false, error: user.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    private

    def sweep_stale_users!
      User.sweep_stale!
    end
  end
end
