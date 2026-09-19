module Api
  module Admin
    class UsersController < ApplicationController
      before_action :require_admin!
      before_action :sweep_stale_users!, only: [ :index ]
      before_action :set_user, only: [ :approve, :destroy, :reset_password, :make_admin ]

      # Lists registered users, optionally filtered by approval_status
      # (?approval_status=PENDING), for the admin Users Dashboard.
      def index
        users = User.order(:approval_status, :username)
        users = users.where(approval_status: params[:approval_status]) if params[:approval_status].present?
        render json: users.map { |u| admin_user_json(u) }
      end

      def approve
        @user.update!(approval_status: User::APPROVED)
        render json: { ok: true, user: admin_user_json(@user) }
      end

      # Also used for "deny" — per spec, a denied user is removed outright,
      # so the frontend just calls delete instead of a separate deny
      # endpoint. Optionally reassigns the departing user's OWNER/BORROWER
      # text on LIBRARY rows to another user first, so deleting an account
      # doesn't leave orphaned name text behind.
      def destroy
        reassign_books!(@user, params[:reassign_books_to]) if params[:reassign_books_to].present?
        @user.destroy!
        render json: { ok: true }
      end

      # Resets the user's password to a random one-time value, shown once
      # here for the admin to relay, and forces a change on next login.
      def reset_password
        temp_password = SecureRandom.alphanumeric(10)
        @user.password = temp_password
        @user.must_change_password = true
        @user.save!
        render json: { ok: true, temp_password: temp_password }
      end

      def make_admin
        @user.update!(admin_status: true)
        render json: { ok: true, user: admin_user_json(@user) }
      end

      private

      def set_user
        @user = User.find_by(user_id: params[:id])
        render json: { ok: false, error: "User does not exist." }, status: :not_found if @user.nil?
      end

      def sweep_stale_users!
        User.sweep_stale!
      end

      def reassign_books!(from_user, to_name)
        from_name = from_user.full_name
        Book.where(OWNER: from_name).update_all(OWNER: to_name)
        Book.where(BORROWER: from_name).update_all(BORROWER: to_name)
      end

      def admin_user_json(u)
        {
          user_id: u.user_id,
          username: u.username,
          first_name: u.first_name,
          last_name: u.last_name,
          admin_status: u.admin_status,
          approval_status: u.approval_status,
          must_change_password: u.must_change_password,
          created_at: u.created_at
        }
      end
    end
  end
end
