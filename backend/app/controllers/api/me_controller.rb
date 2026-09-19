module Api
  class MeController < ApplicationController
    before_action :require_login!

    def show
      render json: user_json(current_user)
    end

    def update_password
      unless current_user.authenticate(params[:old_password].to_s)
        return render json: { ok: false, error: "Current password is incorrect." }, status: :unprocessable_entity
      end

      new_password = params[:new_password].to_s
      confirmation = params[:new_password_confirmation].to_s
      if new_password != confirmation
        return render json: { ok: false, error: "New passwords do not match." }, status: :unprocessable_entity
      end

      current_user.password = new_password
      current_user.must_change_password = false

      if current_user.save
        render json: { ok: true }
      else
        render json: { ok: false, error: current_user.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end
  end
end
