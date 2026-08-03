ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'sqlite3'
require 'json'
require 'fileutils'
require 'tmpdir'

# Point the app at a throwaway DB + image dir BEFORE loading it, so tests
# never touch the real library.db.
TMP_DIR = Dir.mktmpdir('weinberg-test')
ENV['LIBRARY_DB']      = File.join(TMP_DIR, 'test_library.db')
ENV['LIBRARY_IMG_DIR'] = File.join(TMP_DIR, 'img')

# Seed a minimal LIBRARY table with a couple of books.
def seed_db(path)
  db = SQLite3::Database.new(path)
  db.execute(<<~SQL)
    CREATE TABLE LIBRARY (
      ID INTEGER PRIMARY KEY, OWNER INTEGER NOT NULL, BORROWER TEXT,
      LOCATION TEXT, TITLE TEXT NOT NULL, CREATOR TEXT, PUBLISHER TEXT,
      SERIES TEXT, SUBJECT TEXT, CREATION_DATE TEXT, IDENTIFIER TEXT
    )
  SQL
  db.execute(
    'INSERT INTO LIBRARY (ID, OWNER, TITLE, CREATOR, IDENTIFIER) VALUES (?,?,?,?,?)',
    [1, 'Alex Lu', 'Quantum Mechanics', 'Griffiths', 'ISBN : 9780131118928']
  )
  db.execute(
    'INSERT INTO LIBRARY (ID, OWNER, TITLE, CREATOR, IDENTIFIER) VALUES (?,?,?,?,?)',
    [2, 'Sanjay Mathai', 'Topology', 'Munkres', '']
  )
  db.close
end
seed_db(ENV['LIBRARY_DB'])

require_relative '../app'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  JSON_HEADERS = { 'CONTENT_TYPE' => 'application/json' }.freeze

  def app
    Sinatra::Application
  end

  # Fully reset to the seed state before every test (order-independent, since
  # add/remove tests insert and delete rows).
  def setup
    db = SQLite3::Database.new(ENV['LIBRARY_DB'])
    db.execute('DELETE FROM AUDIT_LOG')
    db.execute('DELETE FROM LIBRARY')
    db.execute(
      'INSERT INTO LIBRARY (ID, OWNER, TITLE, CREATOR, IDENTIFIER) VALUES (?,?,?,?,?)',
      [1, 'Alex Lu', 'Quantum Mechanics', 'Griffiths', 'ISBN : 9780131118928']
    )
    db.execute(
      'INSERT INTO LIBRARY (ID, OWNER, TITLE, CREATOR, IDENTIFIER) VALUES (?,?,?,?,?)',
      [2, 'Sanjay Mathai', 'Topology', 'Munkres', '']
    )
    db.close
  end

  def with_db
    db = SQLite3::Database.new(ENV['LIBRARY_DB'])
    db.results_as_hash = true
    yield db
  ensure
    db&.close
  end

  def audit_rows
    with_db { |db| db.execute('SELECT * FROM AUDIT_LOG ORDER BY ID') }
  end

  def book(id)
    with_db { |db| db.execute('SELECT * FROM LIBRARY WHERE ID = ?', [id]).first }
  end

  def patch_json(path, payload)
    patch path, payload.to_json, JSON_HEADERS
  end

  # ── Search (guards the search route) ──────────────────────────────────────

  def test_search_returns_matching_rows
    get '/api/search', q: 'Griffiths'
    assert last_response.ok?
    rows = JSON.parse(last_response.body)
    assert_equal 1, rows.length
    assert_equal 'Quantum Mechanics', rows[0]['TITLE']
  end

  def test_search_multi_token_is_and
    get '/api/search', q: 'Quantum Munkres' # no single book matches both
    assert_empty JSON.parse(last_response.body)
  end

  def test_search_empty_query_returns_empty
    get '/api/search', q: '   '
    assert_equal [], JSON.parse(last_response.body)
  end

  # ── whoami (footer IP) ────────────────────────────────────────────────────

  def test_whoami_returns_ip
    get '/api/whoami'
    assert last_response.ok?
    assert JSON.parse(last_response.body).key?('ip')
  end

  # ── Name required for edits ───────────────────────────────────────────────

  def test_borrower_edit_without_name_is_rejected
    patch_json '/api/book/1/borrower', name: 'Bob'
    assert_equal 400, last_response.status
    assert_equal 0, audit_rows.length
    assert_nil book(1)['BORROWER']
  end

  def test_location_edit_without_name_is_rejected
    patch_json '/api/book/1/location', location: 'Shelf A'
    assert_equal 400, last_response.status
    assert_equal 0, audit_rows.length
    assert_nil book(1)['LOCATION']
  end

  # ── Successful edits write audit rows ─────────────────────────────────────

  def test_borrower_edit_updates_and_audits
    patch_json '/api/book/1/borrower', name: 'Bob', editor: 'Kushal'
    assert last_response.ok?
    assert_equal 'Bob', book(1)['BORROWER']

    rows = audit_rows
    assert_equal 1, rows.length
    a = rows.first
    assert_equal 'BORROWER', a['FIELD']
    assert_nil   a['OLD_VALUE']
    assert_equal 'Bob',      a['NEW_VALUE']
    assert_equal 'Kushal',   a['EDITOR']
    refute_nil   a['IP']
    refute_nil   a['TIMESTAMP']
  end

  def test_location_edit_updates_and_audits
    patch_json '/api/book/2/location', location: 'Shelf C1', editor: 'Yasin'
    assert last_response.ok?
    assert_equal 'Shelf C1', book(2)['LOCATION']
    assert_equal 'LOCATION', audit_rows.first['FIELD']
  end

  def test_clearing_borrower_records_old_value
    patch_json '/api/book/1/borrower', name: 'Bob', editor: 'K'  # check out
    patch_json '/api/book/1/borrower', name: '',    editor: 'K'  # check in
    assert last_response.ok?
    assert_nil book(1)['BORROWER']

    last = audit_rows.last
    assert_equal 'Bob', last['OLD_VALUE']
    assert_nil   last['NEW_VALUE']
  end

  def test_edit_nonexistent_book_returns_404
    patch_json '/api/book/9999/borrower', name: 'X', editor: 'K'
    assert_equal 404, last_response.status
  end

  # ── Per-book history ──────────────────────────────────────────────────────

  def test_history_newest_first
    patch_json '/api/book/1/borrower', name: 'Bob', editor: 'K'
    patch_json '/api/book/1/location', location: 'S1', editor: 'K'

    get '/api/book/1/history'
    assert last_response.ok?
    rows = JSON.parse(last_response.body)
    assert_equal 2, rows.length
    assert_equal 'LOCATION', rows[0]['FIELD'] # newest first
    assert_equal 'BORROWER', rows[1]['FIELD']
  end

  # ── Global audit log ──────────────────────────────────────────────────────

  def test_audit_returns_all_with_titles_newest_first
    patch_json '/api/book/1/borrower', name: 'Bob', editor: 'K'
    patch_json '/api/book/2/location', location: 'S9', editor: 'Y'

    get '/api/audit'
    assert last_response.ok?
    rows = JSON.parse(last_response.body)
    assert_equal 2, rows.length
    assert_equal 2,          rows[0]['BOOK_ID'] # newest first
    assert_equal 'Topology', rows[0]['BOOK_TITLE']
    assert_equal 'Quantum Mechanics', rows[1]['BOOK_TITLE']
  end

  # ── Add a book ────────────────────────────────────────────────────────────

  def test_add_book_without_name_is_rejected
    before = with_db { |db| db.execute('SELECT COUNT(*) FROM LIBRARY')[0][0] }
    post '/api/book', { TITLE: 'New Book', OWNER: 'Alex Lu' }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
    after = with_db { |db| db.execute('SELECT COUNT(*) FROM LIBRARY')[0][0] }
    assert_equal before, after           # nothing inserted
    assert_equal 0, audit_rows.length
  end

  def test_add_book_requires_title_and_owner
    post '/api/book', { TITLE: 'No Owner', editor: 'K' }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
    post '/api/book', { OWNER: 'No Title', editor: 'K' }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
    assert_equal 0, audit_rows.length
  end

  def test_add_book_inserts_and_audits
    payload = { TITLE: 'Real Analysis', OWNER: 'Alex Lu', CREATOR: 'Rudin',
                IDENTIFIER: 'ISBN : 007054234X', editor: 'Kushal' }
    post '/api/book', payload.to_json, JSON_HEADERS
    assert_equal 201, last_response.status

    body = JSON.parse(last_response.body)
    assert body['ok']
    new_id = body['book']['ID']
    refute_nil new_id

    row = book(new_id)
    assert_equal 'Real Analysis', row['TITLE']
    assert_equal 'Alex Lu',       row['OWNER']
    assert_equal 'Rudin',         row['CREATOR']

    a = audit_rows.first
    assert_equal new_id,           a['BOOK_ID']
    assert_equal 'ADDED',          a['FIELD']
    assert_nil   a['OLD_VALUE']
    assert_equal 'Real Analysis',  a['NEW_VALUE']
    assert_equal 'Kushal',         a['EDITOR']
    refute_nil   a['IP']
  end

  def test_add_book_blank_fields_become_null
    post '/api/book', { TITLE: 'T', OWNER: 'O', SERIES: '  ', editor: 'K' }.to_json, JSON_HEADERS
    assert_equal 201, last_response.status
    new_id = JSON.parse(last_response.body)['book']['ID']
    assert_nil book(new_id)['SERIES']
  end

  # ── Remove a book ─────────────────────────────────────────────────────────

  def test_remove_book_without_name_is_rejected
    delete '/api/book/1', { }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
    refute_nil book(1)                    # still present
    assert_equal 0, audit_rows.length
  end

  def test_remove_nonexistent_book_returns_404
    delete '/api/book/9999', { editor: 'K' }.to_json, JSON_HEADERS
    assert_equal 404, last_response.status
  end

  def test_remove_book_deletes_and_audits
    delete '/api/book/1', { editor: 'Yasin' }.to_json, JSON_HEADERS
    assert last_response.ok?
    assert_nil book(1)                     # gone

    a = audit_rows.first
    assert_equal 1,                  a['BOOK_ID']
    assert_equal 'REMOVED',          a['FIELD']
    assert_equal 'Quantum Mechanics', a['OLD_VALUE'] # title preserved in the log
    assert_nil   a['NEW_VALUE']
    assert_equal 'Yasin',            a['EDITOR']
    refute_nil   a['IP']
  end

  def test_removed_book_still_appears_in_audit_log
    delete '/api/book/1', { editor: 'Yasin' }.to_json, JSON_HEADERS
    get '/api/audit'
    rows = JSON.parse(last_response.body)
    entry = rows.find { |r| r['FIELD'] == 'REMOVED' }
    refute_nil entry
    assert_nil entry['BOOK_TITLE']              # LEFT JOIN: row is gone
    assert_equal 'Quantum Mechanics', entry['OLD_VALUE'] # but title survives here
  end

  # ── Thumbnail (no network paths only) ─────────────────────────────────────

  def test_thumbnail_404_when_no_identifiers
    get '/api/book/2/thumbnail' # book 2 has an empty IDENTIFIER
    assert_equal 404, last_response.status
  end

  def test_thumbnail_serves_cached_file
    FileUtils.mkdir_p(ENV['LIBRARY_IMG_DIR'])
    cached = File.join(ENV['LIBRARY_IMG_DIR'], '1.jpg')
    File.binwrite(cached, 'fakejpegbytes')
    get '/api/book/1/thumbnail'
    assert last_response.ok?
    assert_equal 'fakejpegbytes', last_response.body
  ensure
    File.delete(cached) if cached && File.exist?(cached)
  end
end
