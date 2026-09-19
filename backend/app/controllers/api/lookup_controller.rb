module Api
  class LookupController < ApplicationController
    # Look up book metadata by identifier (ISBN / LCCN / OCLC) via
    # OpenLibrary and return it mapped to our columns, so the Add form can
    # auto-populate.
    def show
      isbn = params[:isbn].to_s.strip
      lccn = params[:lccn].to_s.strip
      oclc = params[:oclc].to_s.strip

      bibkey =
        if    !isbn.empty? then "ISBN:#{isbn}"
        elsif !lccn.empty? then "LCCN:#{lccn}"
        elsif !oclc.empty? then "OCLC:#{oclc}"
        end

      return render json: { ok: false, error: "Provide an isbn, lccn, or oclc." }, status: :bad_request if bibkey.nil?

      result = OpenLibraryService.lookup(bibkey)
      case result[:status]
      when :ok
        render json: { ok: true, book: OpenLibraryService.map_to_columns(result[:data]) }
      when :not_found
        render json: { ok: false, error: "No record found in OpenLibrary for that identifier. You can enter the details manually." }, status: :not_found
      else # :error
        render json: { ok: false, error: "The lookup service is temporarily unavailable — please try again, or enter the details manually." }, status: :service_unavailable
      end
    end
  end
end
