ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/mock'
require 'rack/test'
require 'sqlite3'
require 'json'
require 'fileutils'
require 'tmpdir'

# Minimal stand-in for a Net::HTTP response, so lookup tests need no network.
class FakeResp
  def initialize(ok:, body: '', code: '200')
    @ok = ok
    @body = body
    @code = code
  end

  def is_a?(klass)
    klass == Net::HTTPOK ? @ok : super
  end

  attr_reader :body, :code
end

# Point the app at a throwaway DB + image dir BEFORE loading it, so tests
# never touch the real library.db.
TMP_DIR = Dir.mktmpdir('weinberg-test')
ENV['LIBRARY_DB']      = File.join(TMP_DIR, 'test_library.db')
ENV['LIBRARY_IMG_DIR'] = File.join(TMP_DIR, 'img')
ENV['DISABLE_OPENLIBRARY'] = '1' # keep tests offline + deterministic

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

  # ── Identifier lookup / OpenLibrary mapping ───────────────────────────────

  def test_lookup_requires_an_identifier_param
    get '/api/lookup'
    assert_equal 400, last_response.status
  end

  def test_lookup_returns_404_when_genuinely_not_found
    get '/api/lookup', isbn: '9999999999' # DISABLE_OPENLIBRARY='1' -> :not_found -> 404
    assert_equal 404, last_response.status
  end

  def test_lookup_returns_503_on_transient_error
    ENV['DISABLE_OPENLIBRARY'] = 'error'
    get '/api/lookup', isbn: '9781470418847' # a valid ISBN, but service errors
    assert_equal 503, last_response.status
    assert_match(/temporarily unavailable/i, JSON.parse(last_response.body)['error'])
  ensure
    ENV['DISABLE_OPENLIBRARY'] = '1'
  end

  def test_openlibrary_lookup_ok_and_not_found
    ENV.delete('DISABLE_OPENLIBRARY')
    found = FakeResp.new(ok: true, body: { 'ISBN:1' => { 'title' => 'T' } }.to_json)
    stub(:http_get, ->(_uri) { found }) do
      r = openlibrary_lookup('ISBN:1')
      assert_equal :ok, r[:status]
      assert_equal 'T', r[:data]['title']
    end

    empty = FakeResp.new(ok: true, body: '{}')
    stub(:http_get, ->(_uri) { empty }) do
      assert_equal :not_found, openlibrary_lookup('ISBN:1')[:status]
    end
  ensure
    ENV['DISABLE_OPENLIBRARY'] = '1'
  end

  def test_openlibrary_lookup_retries_then_errors_on_transient_failure
    ENV.delete('DISABLE_OPENLIBRARY')
    calls = 0
    raising = ->(_uri) { calls += 1; raise Errno::ECONNREFUSED }
    stub(:http_get, raising) do
      stub(:sleep, nil) do # don't actually wait between retries
        assert_equal :error, openlibrary_lookup('ISBN:1')[:status]
      end
    end
    assert_equal 3, calls # retried up to OPENLIBRARY_MAX_ATTEMPTS
  ensure
    ENV['DISABLE_OPENLIBRARY'] = '1'
  end

  def test_openlibrary_lookup_retries_on_non_200_then_succeeds
    ENV.delete('DISABLE_OPENLIBRARY')
    responses = [
      FakeResp.new(ok: false, code: '503'),
      FakeResp.new(ok: true, body: { 'ISBN:1' => { 'title' => 'Recovered' } }.to_json),
    ]
    stub(:http_get, ->(_uri) { responses.shift }) do
      stub(:sleep, nil) do
        r = openlibrary_lookup('ISBN:1')
        assert_equal :ok, r[:status]
        assert_equal 'Recovered', r[:data]['title']
      end
    end
  ensure
    ENV['DISABLE_OPENLIBRARY'] = '1'
  end

  def test_map_openlibrary_maps_fields
    data = {
      'title'    => 'Introduction to Topology',
      'subtitle' => 'Pure and Applied',
      'authors'  => [{ 'name' => 'Colin Adams' }, { 'name' => 'Robert Franzosa' }],
      'publishers'     => [{ 'name' => 'Pearson' }],
      'publish_places' => [{ 'name' => 'Upper Saddle River' }],
      'publish_date'   => '2008',
      'subjects'       => [{ 'name' => 'Topology' }, 'Mathematics'],
      'identifiers'    => { 'isbn_13' => ['9780131848696'], 'lccn' => ['2007041561'] },
    }
    m = map_openlibrary(data)
    assert_equal 'Introduction to Topology: Pure and Applied', m['TITLE']
    assert_equal 'Colin Adams; Robert Franzosa', m['CREATOR']
    assert_equal 'Upper Saddle River : Pearson, 2008', m['PUBLISHER']
    assert_equal '2008', m['CREATION_DATE']
    assert_equal 'Topology; Mathematics', m['SUBJECT']
    assert_equal 'LC : 2007041561; ISBN : 9780131848696', m['IDENTIFIER']
  end

  def test_identifier_has_isbn_or_lc
    assert identifier_has_isbn_or_lc?('LC : 69017408')
    assert identifier_has_isbn_or_lc?('OCLC : (OCoLC)123; ISBN : 3764354909')
    refute identifier_has_isbn_or_lc?('OCLC : (OCoLC)36307953')
    refute identifier_has_isbn_or_lc?('')
    refute identifier_has_isbn_or_lc?(nil)
  end

  # ── Bulk CSV parsing (pure) ───────────────────────────────────────────────

  def test_parse_bulk_csv_maps_columns_and_line_numbers
    csv = <<~CSV
      Owner,Borrower,Shelf,DD,Title,Creator,Publisher,Edition,Series,Notes,Subject,Creation Date,Identifier
      Alex Lu,,3,QA1,Algebra,Lang,Springer,,,,Math,2002,ISBN : 038795385X
    CSV
    rows = parse_bulk_csv(csv)
    assert_equal 1, rows.length
    r = rows.first
    assert_equal 2, r[:line]
    assert_equal 'Algebra',  r[:values]['TITLE']
    assert_equal 'Alex Lu',  r[:values]['OWNER']
    assert_equal '3',        r[:values]['LOCATION'] # Shelf -> LOCATION
    assert_equal 'ISBN : 038795385X', r[:values]['IDENTIFIER']
    refute r[:values].key?('DD') # dropped column
  end

  def test_parse_bulk_csv_missing_required_headers_raises
    err = assert_raises(ArgumentError) do
      parse_bulk_csv("Owner,Title\nAlex,Algebra\n") # no Identifier column
    end
    assert_match(/Identifier/i, err.message)
  end

  # ── Bulk import endpoint ──────────────────────────────────────────────────

  def test_bulk_requires_name
    post '/api/books/bulk', { csv: "Owner,Title,Identifier\nA,B,ISBN : 1\n" }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
  end

  def test_bulk_missing_headers_returns_400
    post '/api/books/bulk', { editor: 'K', csv: "Owner,Title\nA,B\n" }.to_json, JSON_HEADERS
    assert_equal 400, last_response.status
    assert_match(/Identifier/i, JSON.parse(last_response.body)['error'])
  end

  def test_bulk_imports_valid_rows_and_audits
    csv = <<~CSV
      Owner,Title,Creator,Identifier
      Alex Lu,Algebra,Lang,ISBN : 038795385X
      Sanjay,Analysis,Rudin,LC : 76087199
    CSV
    post '/api/books/bulk', { editor: 'Kushal', csv: csv }.to_json, JSON_HEADERS
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal 2, body['added'].length
    assert_empty body['skipped']

    # Both books exist and each produced an ADDED audit row.
    titles = with_db { |db| db.execute("SELECT TITLE FROM LIBRARY WHERE TITLE IN ('Algebra','Analysis')") }.map { |r| r['TITLE'] }
    assert_equal %w[Algebra Analysis], titles.sort
    added_audits = audit_rows.select { |a| a['FIELD'] == 'ADDED' }
    assert_equal 2, added_audits.length
    assert(added_audits.all? { |a| a['EDITOR'] == 'Kushal' && !a['IP'].nil? })
  end

  def test_bulk_skips_rows_missing_required_fields
    csv = <<~CSV
      Owner,Title,Identifier
      ,No Owner,ISBN : 1
      Alex,Good Book,ISBN : 2
    CSV
    post '/api/books/bulk', { editor: 'K', csv: csv }.to_json, JSON_HEADERS
    body = JSON.parse(last_response.body)
    assert_equal 1, body['added'].length
    assert_equal 1, body['skipped'].length
    assert_equal 2, body['skipped'][0]['line']
    assert_match(/Owner/i, body['skipped'][0]['reason'])
  end

  def test_bulk_skips_rows_without_isbn_or_lc_when_offline
    csv = <<~CSV
      Owner,Title,Identifier
      Alex,No Identifier Book,OCLC : (OCoLC)123
    CSV
    post '/api/books/bulk', { editor: 'K', csv: csv }.to_json, JSON_HEADERS
    body = JSON.parse(last_response.body)
    assert_empty body['added']
    assert_equal 1, body['skipped'].length
    assert_match(/ISBN or LC/i, body['skipped'][0]['reason'])
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
