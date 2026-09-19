module Api
  class WhoamiController < ApplicationController
    # Who is calling? Used by the frontend footer for the audit trail.
    def show
      render json: { ip: request.remote_ip }
    end
  end
end
