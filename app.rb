require 'sinatra'
require 'sqlite3'
require 'json'
require 'net/http'
require 'fileutils'

DB_PATH = File.join(__dir__, 'library.db')
IMG_DIR = File.join(__dir__, 'img')

# Fields searched per token — mirrors db.py search()
SEARCH_FIELDS = %w[
  TITLE CREATOR OWNER LOCATION BORROWER
  PUBLISHER SERIES SUBJECT CREATION_DATE IDENTIFIER
].freeze

# ── CORS ─────────────────────────────────────────────────────────────────────

before do
  headers 'Access-Control-Allow-Origin'  => '*',
          'Access-Control-Allow-Methods' => 'GET, PATCH, OPTIONS',
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

# Runs the given block inside a BEGIN IMMEDIATE transaction.
# Returns [status_code, json_body].
def write_tx(db)
  db.transaction('immediate') { yield }
  [200, { ok: true }.to_json]
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

patch '/api/book/:id/borrower' do
  content_type :json
  book_id   = params[:id].to_i
  body_data = (JSON.parse(request.body.read) rescue {})
  name      = body_data.fetch('name', '').to_s.strip

  db = open_db
  code, body = write_tx(db) do
    db.execute('UPDATE LIBRARY SET BORROWER = ? WHERE ID = ?',
               [name.empty? ? nil : name, book_id])
  end
  db.close
  status code
  body
end

patch '/api/book/:id/location' do
  content_type :json
  book_id   = params[:id].to_i
  body_data = (JSON.parse(request.body.read) rescue {})
  location  = body_data.fetch('location', '').to_s.strip

  db = open_db
  code, body = write_tx(db) do
    db.execute('UPDATE LIBRARY SET LOCATION = ? WHERE ID = ?',
               [location.empty? ? nil : location, book_id])
  end
  db.close
  status code
  body
end

# ── Server config ─────────────────────────────────────────────────────────────

set :port, ENV.fetch('PORT', 4567).to_i
set :bind, '0.0.0.0'
