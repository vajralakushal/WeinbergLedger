module Api
  class BooksController < ApplicationController
    before_action :require_login!, only: [ :update_borrower, :update_location, :create, :bulk_create, :destroy ]

    def search
      q = params[:q].to_s.strip
      return render json: [] if q.empty?

      books = Book.search(q, fields: Array(params[:fields]))
      render json: books.map(&:attributes)
    end

    def thumbnail
      book_id  = params[:id].to_i
      img_path = File.join(img_dir, "#{book_id}.jpg")
      return send_file(img_path, type: "image/jpeg", disposition: "inline") if File.exist?(img_path)

      book = Book.find_by(ID: book_id)
      return head :not_found if book.nil?

      identifiers = book.identifiers
      return head :not_found if identifiers.key?("Error")

      cached = OpenLibraryService.fetch_cover(img_path, identifiers)
      cached ? send_file(cached, type: "image/jpeg", disposition: "inline") : head(:not_found)
    end

    def history
      book_id = params[:id].to_i
      rows = AuditLog.where(BOOK_ID: book_id).order(ID: :desc)
      render json: rows.map { |r| r.attributes.slice("FIELD", "OLD_VALUE", "NEW_VALUE", "EDITOR", "IP", "TIMESTAMP") }
    end

    def update_borrower
      name = params[:name].to_s.strip
      apply_edit(params[:id].to_i, "BORROWER", name.empty? ? nil : name, current_user.full_name)
    end

    def update_location
      location = params[:location].to_s.strip
      apply_edit(params[:id].to_i, "LOCATION", location.empty? ? nil : location, current_user.full_name)
    end

    def create
      values = Book::COLUMNS.index_with { |col| params[col].to_s.strip.presence }

      if values["TITLE"].nil? || values["OWNER"].nil?
        return render json: { ok: false, error: "Title and Owner are required." }, status: :bad_request
      end

      book = nil
      ActiveRecord::Base.transaction do
        book = Book.create!(values)
        AuditLog.record!(book_id: book.ID, field: "ADDED", old_value: nil,
                          new_value: values["TITLE"], editor: current_user.full_name, ip: request.remote_ip)
      end
      render json: { ok: true, book: values.merge("ID" => book.ID) }, status: :created
    end

    def bulk_create
      begin
        rows = BulkCsvImporter.parse(params[:csv])
      rescue ArgumentError => e
        return render json: { ok: false, error: e.message }, status: :bad_request
      end
      return render json: { ok: false, error: "No data rows found in the CSV." }, status: :bad_request if rows.empty?

      # Old books often have no ISBN/LC at all. Rather than silently drop
      # them, the frontend asks the user to confirm before adding them
      # without an identifier, then resubmits just those rows with this set.
      force_no_identifier = ActiveModel::Type::Boolean.new.cast(params[:force_no_identifier])

      to_insert = []
      skipped   = []
      rows.each do |r|
        v    = r[:values]
        errs = []
        errs << "Title required" if v["TITLE"].to_s.strip.empty?
        errs << "Owner required" if v["OWNER"].to_s.strip.empty?
        unless errs.empty?
          skipped << { line: r[:line], reason: errs.join(", ") }
          next
        end

        unless BulkCsvImporter.identifier_has_isbn_or_lc?(v["IDENTIFIER"])
          isbn = OpenLibraryService.find_isbn(v["TITLE"], v["CREATOR"])
          if isbn
            v["IDENTIFIER"] = [ v["IDENTIFIER"], "ISBN : #{isbn}" ].compact.reject(&:empty?).join("; ")
          elsif !force_no_identifier
            skipped << { line: r[:line], title: v["TITLE"], reason: "No ISBN or LC (and none found online)", missing_identifier: true }
            next
          end
        end
        to_insert << r
      end

      added = []
      ActiveRecord::Base.transaction do
        to_insert.each do |r|
          v = r[:values]
          book = Book.create!(v)
          AuditLog.record!(book_id: book.ID, field: "ADDED", old_value: nil,
                            new_value: v["TITLE"], editor: current_user.full_name, ip: request.remote_ip)
          added << { line: r[:line], id: book.ID, title: v["TITLE"] }
        end
      end

      render json: { ok: true, added: added, skipped: skipped }
    end

    def destroy
      book_id = params[:id].to_i
      ActiveRecord::Base.transaction do
        book = Book.find_by(ID: book_id)
        if book.nil?
          render json: { ok: false, error: "Book does not exist." }, status: :not_found
        else
          title = book.TITLE
          book.destroy!
          AuditLog.record!(book_id: book_id, field: "REMOVED", old_value: title,
                            new_value: nil, editor: current_user.full_name, ip: request.remote_ip)
          render json: { ok: true }
        end
      end
    end

    private

    def img_dir
      ENV.fetch("LIBRARY_IMG_DIR") { Rails.root.join("..", "img").to_s }
    end

    # Ported from app.rb's apply_edit — updates one whitelisted column and
    # records an audit row in the same immediate transaction.
    def apply_edit(book_id, column, new_value, editor)
      ActiveRecord::Base.transaction do
        book = Book.find_by(ID: book_id)
        if book.nil?
          render json: { ok: false, error: "Book does not exist." }, status: :not_found
        else
          old_value = book[column]
          book.update!(column => new_value)
          AuditLog.record!(book_id: book_id, field: column, old_value: old_value,
                            new_value: new_value, editor: editor, ip: request.remote_ip)
          render json: { ok: true }
        end
      end
    end
  end
end
