require 'sinatra'
require 'sqlite3'
require 'json'
require 'net/http'
require 'fileutils'
require 'time'
require 'csv'

# Overridable so tests can point at a throwaway DB / image dir.
DB_PATH = ENV.fetch('LIBRARY_DB')      { File.join(__dir__, 'library.db') }
IMG_DIR = ENV.fetch('LIBRARY_IMG_DIR') { File.join(__dir__, 'img') }

# Fields searched per token — mirrors db.py search()
SEARCH_FIELDS = %w[
  TITLE CREATOR OWNER LOCATION BORROWER
  PUBLISHER SERIES SUBJECT CREATION_DATE IDENTIFIER
].freeze

# ── CORS ─────────────────────────────────────────────────────────────────────

before do
  headers 'Access-Control-Allow-Origin'  => '*',
          'Access-Control-Allow-Methods' => 'GET, POST, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
  200
end

# ── DB helpers ────────────────────────────────────────────────────────────────

def open_db
  db = SQLite3::Database.new(DB_PATH)
  db.execute('PRAGMA journal_mode=WAL')
  db
end

# Every edit is recorded here — name + IP + what changed + when.
# No auth by design; this table IS the accountability record.
def ensure_audit_table
  db = open_db
  db.execute(<<~SQL)
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
  db.close
end

# Replicates db.py search():
# tokenise query → for each token OR across all fields → AND across tokens.
def db_search(db, query)
  tokens = query.to_s.strip.split
  return [] if tokens.empty?

  per_token = SEARCH_FIELDS.map { |f| "#{f} LIKE ?" }.join(' OR ')
  where     = tokens.map { "(#{per_token})" }.join(' AND ')
  params    = tokens.flat_map { |t| ["%#{t}%"] * SEARCH_FIELDS.length }

  result  = db.execute2("SELECT * FROM LIBRARY WHERE #{where}", params)
  columns = result[0]
  result[1..].map { |row| columns.zip(row).to_h }
end

# Replicates db.py extract_identifers() — parses the IDENTIFIER field.
def extract_identifiers(db, book_id)
  rows = db.execute('SELECT IDENTIFIER FROM LIBRARY WHERE ID = ?', [book_id])
  return { 'Error' => 'Book does not exist' } if rows.empty?

  id_str = rows[0][0].to_s
  return { 'Error' => 'No identifiers exist' } if id_str.length < 3

  result = {}
  id_str.split('; ').each do |entry|
    parts = entry.strip.split(' : ', 2)
    next unless parts.length == 2

    id_type, value_part = parts[0].strip, parts[1].strip

    record = if id_type == 'OCLC'
      { 'value' => value_part.sub(/^\(OCoLC\)(oc[a-z]+)?/, '') }
    elsif (m = value_part.match(/^(\S+)\s+(\(.+\))$/))
      { 'value' => m[1], 'qualifier' => m[2] }
    else
      { 'value' => value_part }
    end

    result[id_type] ||= []
    result[id_type] << record
  end
  result
end

# Try each identifier against the OpenLibrary Covers API.
# Saves to img/ on first hit and returns the path; nil on failure.
def fetch_cover(img_path, identifiers)
  key_map = [['LC', 'lccn'], ['ISBN', 'isbn'], ['OCLC', 'oclc']]
  catch(:found) do
    key_map.each do |db_key, ol_key|
      (identifiers[db_key] || []).each do |entry|
        value = entry['value'].to_s.strip
        next if value.empty?

        uri = URI("https://covers.openlibrary.org/b/#{ol_key}/#{value}-M.jpg?default=false")
        begin
          resp = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: true, read_timeout: 6, open_timeout: 6) do |http|
            http.get(uri.request_uri)
          end
          next unless resp.is_a?(Net::HTTPOK)
          next unless resp['content-type']&.include?('image')

          FileUtils.mkdir_p(IMG_DIR)
          File.binwrite(img_path, resp.body)
          throw :found, img_path
        rescue StandardError
          next
        end
      end
    end
    nil
  end
end

# Records one audit row. FIELD is a column name for edits, or 'ADDED'/'REMOVED'
# for whole-book lifecycle events. Every row carries the editor's name + IP.
def record_audit(db, book_id, field, old_value, new_value, editor, ip)
  db.execute(<<~SQL, [book_id, field, old_value, new_value, editor, ip, Time.now.utc.iso8601])
    INSERT INTO AUDIT_LOG
      (BOOK_ID, FIELD, OLD_VALUE, NEW_VALUE, EDITOR, IP, TIMESTAMP)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  SQL
end

# Columns a user may set when adding a book (mirrors the DB schema minus ID).
BOOK_COLUMNS = %w[
  OWNER BORROWER LOCATION TITLE CREATOR
  PUBLISHER SERIES SUBJECT CREATION_DATE IDENTIFIER
].freeze

# ── OpenLibrary metadata lookup ────────────────────────────────────────────────

def http_get(uri)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                  read_timeout: 8, open_timeout: 6) do |http|
    http.get(uri.request_uri)
  end
end

# Look up one bib key (e.g. "ISBN:9780131118928") via the OpenLibrary Books API.
# Returns the raw data hash for that key, or nil if not found / on any error.
# Set DISABLE_OPENLIBRARY=1 to force offline behaviour (used in tests).
def openlibrary_lookup(bibkey)
  return nil if ENV['DISABLE_OPENLIBRARY'] == '1'

  uri  = URI("https://openlibrary.org/api/books?bibkeys=#{URI.encode_www_form_component(bibkey)}&format=json&jscmd=data")
  resp = http_get(uri)
  return nil unless resp.is_a?(Net::HTTPOK)

  JSON.parse(resp.body)[bibkey]
rescue StandardError
  nil
end

# Best-effort: find an ISBN from title (+ creator) via the OpenLibrary Search
# API. Returns an ISBN string or nil.
def find_isbn(title, creator)
  return nil if ENV['DISABLE_OPENLIBRARY'] == '1'
  return nil if title.to_s.strip.empty?

  query = { title: title, fields: 'isbn', limit: 1 }
  query[:author] = creator unless creator.to_s.strip.empty?
  uri  = URI("https://openlibrary.org/search.json?#{URI.encode_www_form(query)}")
  resp = http_get(uri)
  return nil unless resp.is_a?(Net::HTTPOK)

  docs = JSON.parse(resp.body)['docs'] || []
  docs.first && Array(docs.first['isbn']).first
rescue StandardError
  nil
end

# Maps an OpenLibrary "data" hash to our DB columns. Pure (no network) so it is
# easy to test. Only non-empty fields are included.
def map_openlibrary(data)
  data ||= {}
  result = {}

  title    = data['title'].to_s.strip
  subtitle = data['subtitle'].to_s.strip
  result['TITLE'] = subtitle.empty? ? title : "#{title}: #{subtitle}" unless title.empty?

  authors = Array(data['authors']).map { |a| a['name'] }.compact
  result['CREATOR'] = authors.join('; ') unless authors.empty?

  place      = Array(data['publish_places']).map { |p| p['name'] }.compact.first
  publishers = Array(data['publishers']).map { |p| p['name'] }.compact.join(', ')
  date       = data['publish_date'].to_s.strip
  left       = [place, (publishers.empty? ? nil : publishers)].compact.join(' : ')
  publisher  = [left.empty? ? nil : left, date.empty? ? nil : date].compact.join(', ')
  result['PUBLISHER'] = publisher unless publisher.empty?

  series = Array(data['series']).map(&:to_s).reject(&:empty?)
  result['SERIES'] = series.join('; ') unless series.empty?

  subjects = Array(data['subjects']).map { |s| s.is_a?(Hash) ? s['name'] : s }.compact
  result['SUBJECT'] = subjects.first(12).join('; ') unless subjects.empty?

  if (m = date.match(/\d{4}/))
    result['CREATION_DATE'] = m[0]
  end

  ids   = data['identifiers'] || {}
  lccn  = Array(ids['lccn']).first
  isbn  = Array(ids['isbn_13']).first || Array(ids['isbn_10']).first
  oclc  = Array(ids['oclc']).first
  parts = []
  parts << "LC : #{lccn}"            if lccn
  parts << "ISBN : #{isbn}"          if isbn
  parts << "OCLC : (OCoLC)#{oclc}"   if oclc
  result['IDENTIFIER'] = parts.join('; ') unless parts.empty?

  result
end

# ── Bulk CSV parsing ───────────────────────────────────────────────────────────

# CSV header (lowercased) → DB column. DD / Edition / Notes are intentionally
# dropped (no matching column), matching the original import.
CSV_HEADER_MAP = {
  'owner' => 'OWNER', 'borrower' => 'BORROWER', 'shelf' => 'LOCATION',
  'title' => 'TITLE', 'creator' => 'CREATOR', 'publisher' => 'PUBLISHER',
  'series' => 'SERIES', 'subject' => 'SUBJECT',
  'creation date' => 'CREATION_DATE', 'identifier' => 'IDENTIFIER'
}.freeze

REQUIRED_CSV_HEADERS = %w[title owner identifier].freeze

# True if the identifier string carries an ISBN or LC/LCCN entry.
def identifier_has_isbn_or_lc?(str)
  str.to_s.match?(/(?:\A|;)\s*(?:ISBN|LCCN|LC)\s*:/i)
end

# Parses bulk CSV text into rows keyed by DB column. Raises ArgumentError with a
# human-readable message on malformed CSV or missing required headers. Returns
# an array of { line:, values: { DB_COL => str|nil } }.
def parse_bulk_csv(text)
  table   = CSV.parse(text.to_s, headers: true)
  headers = Array(table.headers).compact.map { |h| h.to_s.strip.downcase }

  missing = REQUIRED_CSV_HEADERS - headers
  unless missing.empty?
    raise ArgumentError, "Missing required column(s): #{missing.map(&:capitalize).join(', ')}"
  end

  table.each_with_index.map do |row, i|
    values = {}
    row.each do |header, value|
      key = CSV_HEADER_MAP[header.to_s.strip.downcase]
      next unless key

      v = value.to_s.strip
      values[key] = v.empty? ? nil : v
    end
    { line: i + 2, values: values } # header is line 1; data starts at line 2
  end
rescue CSV::MalformedCSVError => e
  raise ArgumentError, "Malformed CSV: #{e.message}"
end

# Updates one whitelisted column and records an audit row in the same
# BEGIN IMMEDIATE transaction. `column` comes only from the fixed route
# handlers below, so it is safe to interpolate. Returns [status_code, json_body].
def apply_edit(db, book_id, column, new_value, editor, ip)
  result = nil
  db.transaction('immediate') do
    old_rows = db.execute("SELECT #{column} FROM LIBRARY WHERE ID = ?", [book_id])
    if old_rows.empty?
      result = [404, { ok: false, error: 'Book does not exist.' }.to_json]
    else
      old_value = old_rows[0][0]
      db.execute("UPDATE LIBRARY SET #{column} = ? WHERE ID = ?", [new_value, book_id])
      record_audit(db, book_id, column, old_value, new_value, editor, ip)
      result = [200, { ok: true }.to_json]
    end
  end
  result
rescue SQLite3::Exception
  [503, { ok: false, error: 'Database is locked by another process.' }.to_json]
end

# ── Routes ────────────────────────────────────────────────────────────────────

get '/api/search' do
  content_type :json
  q = params[:q].to_s.strip
  return [].to_json if q.empty?

  db   = open_db
  rows = db_search(db, q)
  db.close
  rows.to_json
end

get '/api/book/:id/thumbnail' do
  book_id  = params[:id].to_i
  img_path = File.join(IMG_DIR, "#{book_id}.jpg")

  return send_file(img_path, type: 'image/jpeg') if File.exist?(img_path)

  db          = open_db
  identifiers = extract_identifiers(db, book_id)
  db.close

  halt 404 if identifiers.key?('Error')

  cached = fetch_cover(img_path, identifiers)
  cached ? send_file(cached, type: 'image/jpeg') : halt(404)
end

# Who is calling? Used by the frontend footer for the audit trail.
get '/api/whoami' do
  content_type :json
  { ip: request.ip }.to_json
end

# The complete audit trail across all books, newest first, joined with the
# book title for context. The frontend filters by person client-side.
get '/api/audit' do
  content_type :json

  db     = open_db
  result = db.execute2(<<~SQL)
    SELECT a.BOOK_ID, l.TITLE AS BOOK_TITLE, a.FIELD, a.OLD_VALUE,
           a.NEW_VALUE, a.EDITOR, a.IP, a.TIMESTAMP
    FROM AUDIT_LOG a
    LEFT JOIN LIBRARY l ON l.ID = a.BOOK_ID
    ORDER BY a.ID DESC
  SQL
  db.close

  columns = result[0]
  result[1..].map { |row| columns.zip(row).to_h }.to_json
end

# Full change history for one book, newest first.
get '/api/book/:id/history' do
  content_type :json
  book_id = params[:id].to_i

  db     = open_db
  result = db.execute2(<<~SQL, [book_id])
    SELECT FIELD, OLD_VALUE, NEW_VALUE, EDITOR, IP, TIMESTAMP
    FROM AUDIT_LOG WHERE BOOK_ID = ? ORDER BY ID DESC
  SQL
  db.close

  columns = result[0]
  result[1..].map { |row| columns.zip(row).to_h }.to_json
end

patch '/api/book/:id/borrower' do
  content_type :json
  book_id   = params[:id].to_i
  body_data = (JSON.parse(request.body.read) rescue {})
  name      = body_data.fetch('name', '').to_s.strip
  editor    = body_data.fetch('editor', '').to_s.strip

  halt 400, { ok: false, error: 'Your name is required to make an edit.' }.to_json if editor.empty?

  db = open_db
  code, body = apply_edit(db, book_id, 'BORROWER', name.empty? ? nil : name, editor, request.ip)
  db.close
  status code
  body
end

patch '/api/book/:id/location' do
  content_type :json
  book_id   = params[:id].to_i
  body_data = (JSON.parse(request.body.read) rescue {})
  location  = body_data.fetch('location', '').to_s.strip
  editor    = body_data.fetch('editor', '').to_s.strip

  halt 400, { ok: false, error: 'Your name is required to make an edit.' }.to_json if editor.empty?

  db = open_db
  code, body = apply_edit(db, book_id, 'LOCATION', location.empty? ? nil : location, editor, request.ip)
  db.close
  status code
  body
end

# Look up book metadata by identifier (ISBN / LCCN / OCLC) via OpenLibrary and
# return it mapped to our columns, so the Add form can auto-populate.
get '/api/lookup' do
  content_type :json
  isbn = params[:isbn].to_s.strip
  lccn = params[:lccn].to_s.strip
  oclc = params[:oclc].to_s.strip

  bibkey =
    if    !isbn.empty? then "ISBN:#{isbn}"
    elsif !lccn.empty? then "LCCN:#{lccn}"
    elsif !oclc.empty? then "OCLC:#{oclc}"
    end

  halt 400, { ok: false, error: 'Provide an isbn, lccn, or oclc.' }.to_json if bibkey.nil?

  data = openlibrary_lookup(bibkey)
  halt 404, { ok: false, error: 'No match found for that identifier.' }.to_json if data.nil?

  { ok: true, book: map_openlibrary(data) }.to_json
end

# Bulk-add books from CSV text (same shape as the source spreadsheet). Requires
# the editor's name. Each row must have Title + Owner and an ISBN or LC; a
# missing identifier is looked up online (best effort), else the row is skipped.
# Returns a per-row report and records an 'ADDED' audit row for each insert.
post '/api/books/bulk' do
  content_type :json
  body_data = (JSON.parse(request.body.read) rescue {})
  editor    = body_data.fetch('editor', '').to_s.strip
  halt 400, { ok: false, error: 'Your name is required to add books.' }.to_json if editor.empty?

  begin
    rows = parse_bulk_csv(body_data.fetch('csv', ''))
  rescue ArgumentError => e
    halt 400, { ok: false, error: e.message }.to_json
  end
  halt 400, { ok: false, error: 'No data rows found in the CSV.' }.to_json if rows.empty?

  # Phase 1 — validate + best-effort ISBN lookup (no DB lock held here).
  to_insert = []
  skipped   = []
  rows.each do |r|
    v    = r[:values]
    errs = []
    errs << 'Title required' if v['TITLE'].to_s.strip.empty?
    errs << 'Owner required' if v['OWNER'].to_s.strip.empty?
    unless errs.empty?
      skipped << { line: r[:line], reason: errs.join(', ') }
      next
    end

    unless identifier_has_isbn_or_lc?(v['IDENTIFIER'])
      isbn = find_isbn(v['TITLE'], v['CREATOR'])
      if isbn
        v['IDENTIFIER'] = [v['IDENTIFIER'], "ISBN : #{isbn}"].compact.reject(&:empty?).join('; ')
      else
        skipped << { line: r[:line], reason: 'No ISBN or LC (and none found online)' }
        next
      end
    end
    to_insert << r
  end

  # Phase 2 — insert the valid rows in one transaction.
  added        = []
  db           = open_db
  placeholders = (['?'] * BOOK_COLUMNS.length).join(', ')
  begin
    db.transaction('immediate') do
      to_insert.each do |r|
        v = r[:values]
        db.execute(
          "INSERT INTO LIBRARY (#{BOOK_COLUMNS.join(', ')}) VALUES (#{placeholders})",
          BOOK_COLUMNS.map { |c| v[c] }
        )
        new_id = db.last_insert_row_id
        record_audit(db, new_id, 'ADDED', nil, v['TITLE'], editor, request.ip)
        added << { line: r[:line], id: new_id, title: v['TITLE'] }
      end
    end
  rescue SQLite3::Exception
    db.close
    halt 503, { ok: false, error: 'Database is locked by another process.' }.to_json
  end
  db.close

  { ok: true, added: added, skipped: skipped }.to_json
end

# Add a new book. Requires the editor's name; TITLE and OWNER are mandatory
# (schema NOT NULL). Records an 'ADDED' audit row with the editor + IP.
post '/api/book' do
  content_type :json
  body_data = (JSON.parse(request.body.read) rescue {})
  editor    = body_data.fetch('editor', '').to_s.strip
  halt 400, { ok: false, error: 'Your name is required to add a book.' }.to_json if editor.empty?

  # Pull only known columns; blanks become NULL.
  values = BOOK_COLUMNS.to_h do |col|
    v = body_data.fetch(col, '').to_s.strip
    [col, v.empty? ? nil : v]
  end

  if values['TITLE'].nil? || values['OWNER'].nil?
    halt 400, { ok: false, error: 'Title and Owner are required.' }.to_json
  end

  db          = open_db
  placeholders = (['?'] * BOOK_COLUMNS.length).join(', ')
  begin
    new_id = nil
    db.transaction('immediate') do
      db.execute(
        "INSERT INTO LIBRARY (#{BOOK_COLUMNS.join(', ')}) VALUES (#{placeholders})",
        BOOK_COLUMNS.map { |c| values[c] }
      )
      new_id = db.last_insert_row_id
      record_audit(db, new_id, 'ADDED', nil, values['TITLE'], editor, request.ip)
    end
    status 201
    { ok: true, book: values.merge('ID' => new_id) }.to_json
  rescue SQLite3::Exception
    status 503
    { ok: false, error: 'Database is locked by another process.' }.to_json
  ensure
    db.close
  end
end

# Remove a book. Requires the editor's name; records a 'REMOVED' audit row
# (keeping the title in OLD_VALUE, since the LIBRARY row is gone afterward).
delete '/api/book/:id' do
  content_type :json
  book_id   = params[:id].to_i
  body_data = (JSON.parse(request.body.read) rescue {})
  editor    = body_data.fetch('editor', '').to_s.strip
  halt 400, { ok: false, error: 'Your name is required to remove a book.' }.to_json if editor.empty?

  db = open_db
  begin
    result = nil
    db.transaction('immediate') do
      rows = db.execute('SELECT TITLE FROM LIBRARY WHERE ID = ?', [book_id])
      if rows.empty?
        result = [404, { ok: false, error: 'Book does not exist.' }.to_json]
      else
        title = rows[0][0]
        db.execute('DELETE FROM LIBRARY WHERE ID = ?', [book_id])
        record_audit(db, book_id, 'REMOVED', title, nil, editor, request.ip)
        result = [200, { ok: true }.to_json]
      end
    end
    status result[0]
    result[1]
  rescue SQLite3::Exception
    status 503
    { ok: false, error: 'Database is locked by another process.' }.to_json
  ensure
    db.close
  end
end

# ── Server config ─────────────────────────────────────────────────────────────

ensure_audit_table

set :port, ENV.fetch('PORT', 4567).to_i
set :bind, '0.0.0.0'
