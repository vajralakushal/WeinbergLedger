module Api
  class AuditController < ApplicationController
    # The complete audit trail across all books, newest first, joined with
    # the book title for context. The frontend filters by person client-side.
    def index
      sql = <<~SQL
        SELECT a.BOOK_ID, l.TITLE AS BOOK_TITLE, a.FIELD, a.OLD_VALUE,
               a.NEW_VALUE, a.EDITOR, a.IP, a.TIMESTAMP
        FROM AUDIT_LOG a
        LEFT JOIN LIBRARY l ON l.ID = a.BOOK_ID
        ORDER BY a.ID DESC
      SQL
      render json: ActiveRecord::Base.connection.select_all(sql).to_a
    end
  end
end
