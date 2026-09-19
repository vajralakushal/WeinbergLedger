# Recreates the two tables the old Sinatra app (app.rb) bootstrapped itself
# (LIBRARY was shipped pre-populated in the committed library.db; AUDIT_LOG
# was created idempotently on boot via ensure_audit_table). Written as raw
# SQL with IF NOT EXISTS, matching the exact existing schema byte-for-byte,
# so this migration is a no-op against the real library.db (which already
# has these tables and data) but still bootstraps a fresh/test database.
class CreateLibraryAndAuditLog < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS LIBRARY (
        ID            INTEGER PRIMARY KEY,
        OWNER         INTEGER NOT NULL,
        BORROWER      TEXT,
        LOCATION      TEXT,
        TITLE         TEXT NOT NULL,
        CREATOR       TEXT,
        PUBLISHER     TEXT,
        SERIES        TEXT,
        SUBJECT       TEXT,
        CREATION_DATE TEXT,
        IDENTIFIER    TEXT
      )
    SQL

    execute <<~SQL
      CREATE TABLE IF NOT EXISTS AUDIT_LOG (
        ID        INTEGER PRIMARY KEY AUTOINCREMENT,
        BOOK_ID   INTEGER NOT NULL,
        FIELD     TEXT    NOT NULL,
        OLD_VALUE TEXT,
        NEW_VALUE TEXT,
        EDITOR    TEXT    NOT NULL,
        IP        TEXT,
        TIMESTAMP TEXT    NOT NULL
      )
    SQL
  end

  def down
    drop_table :AUDIT_LOG, if_exists: true
    drop_table :LIBRARY, if_exists: true
  end
end
