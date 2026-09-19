require "test_helper"

# Ported from the old Sinatra suite (test/app_test.rb) — same flat test_*
# style and direct-DB assertions, now against the Rails routes/controllers.
# Book-mutating routes require login (see Api::BooksController); the
# free-text `editor` param the old app accepted is gone — EDITOR is now
# derived server-side from the logged-in user.
class ApiTest < ActionDispatch::IntegrationTest
  setup do
    seed_library!
    @user  = create_user!
    @auth  = auth_headers_for(@user)
  end

  def audit_rows
    AuditLog.order(:ID)
  end

  def book(id)
    Book.find_by(ID: id)
  end

  # auth_headers is a trailing positional (not keyword) argument on purpose —
  # Ruby 3 won't let a call site pass an implicit "key: value, ..." payload
  # hash once the method also declares keyword params, so plain call sites
  # like `patch_json path, name: "Bob"` would break if auth were `auth: ...`.
  def patch_json(path, payload, auth_headers = @auth)
    patch path, params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_headers)
  end

  def post_json(path, payload, auth_headers = @auth)
    post path, params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_headers)
  end

  def delete_json(path, payload, auth_headers = @auth)
    delete path, params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_headers)
  end

  # ── Search (guards the search route) ──────────────────────────────────────

  test "search returns matching rows" do
    get "/api/search", params: { q: "Griffiths" }
    assert_response :success
    rows = response.parsed_body
    assert_equal 1, rows.length
    assert_equal "Quantum Mechanics", rows[0]["TITLE"]
  end

  test "search multi token is AND" do
    get "/api/search", params: { q: "Quantum Munkres" } # no single book matches both
    assert_empty response.parsed_body
  end

  test "search empty query returns empty" do
    get "/api/search", params: { q: "   " }
    assert_equal [], response.parsed_body
  end

  test "search can be isolated to specific fields" do
    # "Munkres" only appears in CREATOR; scoping to TITLE should miss it.
    get "/api/search", params: { q: "Munkres", fields: [ "TITLE" ] }
    assert_empty response.parsed_body

    get "/api/search", params: { q: "Munkres", fields: [ "CREATOR" ] }
    rows = response.parsed_body
    assert_equal 1, rows.length
    assert_equal "Topology", rows[0]["TITLE"]
  end

  # ── whoami (footer IP) ────────────────────────────────────────────────────

  test "whoami returns ip" do
    get "/api/whoami"
    assert_response :success
    assert response.parsed_body.key?("ip")
  end

  # ── Writes require login ──────────────────────────────────────────────────

  test "borrower edit without login is rejected" do
    patch_json "/api/book/1/borrower", { name: "Bob" }, {}
    assert_response :unauthorized
    assert_equal 0, audit_rows.length
    assert_nil book(1)["BORROWER"]
  end

  test "location edit without login is rejected" do
    patch_json "/api/book/1/location", { location: "Shelf A" }, {}
    assert_response :unauthorized
    assert_equal 0, audit_rows.length
    assert_nil book(1)["LOCATION"]
  end

  # ── Successful edits write audit rows ─────────────────────────────────────

  test "borrower edit updates and audits" do
    patch_json "/api/book/1/borrower", name: "Bob"
    assert_response :success
    assert_equal "Bob", book(1)["BORROWER"]

    rows = audit_rows
    assert_equal 1, rows.length
    a = rows.first
    assert_equal "BORROWER", a["FIELD"]
    assert_nil   a["OLD_VALUE"]
    assert_equal "Bob",          a["NEW_VALUE"]
    assert_equal @user.full_name, a["EDITOR"]
    refute_nil   a["IP"]
    refute_nil   a["TIMESTAMP"]
  end

  test "location edit updates and audits" do
    patch_json "/api/book/2/location", location: "Shelf C1"
    assert_response :success
    assert_equal "Shelf C1", book(2)["LOCATION"]
    assert_equal "LOCATION", audit_rows.first["FIELD"]
    assert_equal @user.full_name, audit_rows.first["EDITOR"]
  end

  test "clearing borrower records old value" do
    patch_json "/api/book/1/borrower", name: "Bob" # check out
    patch_json "/api/book/1/borrower", name: ""    # check in
    assert_response :success
    assert_nil book(1)["BORROWER"]

    last = audit_rows.last
    assert_equal "Bob", last["OLD_VALUE"]
    assert_nil   last["NEW_VALUE"]
  end

  test "edit nonexistent book returns 404" do
    patch_json "/api/book/9999/borrower", name: "X"
    assert_response :not_found
  end

  # ── Per-book history ──────────────────────────────────────────────────────

  test "history newest first" do
    patch_json "/api/book/1/borrower", name: "Bob"
    patch_json "/api/book/1/location", location: "S1"

    get "/api/book/1/history"
    assert_response :success
    rows = response.parsed_body
    assert_equal 2, rows.length
    assert_equal "LOCATION", rows[0]["FIELD"] # newest first
    assert_equal "BORROWER", rows[1]["FIELD"]
  end

  # ── Global audit log ──────────────────────────────────────────────────────

  test "audit returns all with titles newest first" do
    patch_json "/api/book/1/borrower", name: "Bob"
    patch_json "/api/book/2/location", location: "S9"

    get "/api/audit"
    assert_response :success
    rows = response.parsed_body
    assert_equal 2, rows.length
    assert_equal 2,          rows[0]["BOOK_ID"] # newest first
    assert_equal "Topology", rows[0]["BOOK_TITLE"]
    assert_equal "Quantum Mechanics", rows[1]["BOOK_TITLE"]
  end

  # ── Add a book ────────────────────────────────────────────────────────────

  test "add book without login is rejected" do
    before = Book.count
    post_json "/api/book", { TITLE: "New Book", OWNER: "Alex Lu" }, {}
    assert_response :unauthorized
    assert_equal before, Book.count # nothing inserted
    assert_equal 0, audit_rows.length
  end

  test "add book requires title and owner" do
    post_json "/api/book", TITLE: "No Owner"
    assert_response :bad_request
    post_json "/api/book", OWNER: "No Title"
    assert_response :bad_request
    assert_equal 0, audit_rows.length
  end

  test "add book inserts and audits" do
    post_json "/api/book", TITLE: "Real Analysis", OWNER: "Alex Lu", CREATOR: "Rudin",
                            IDENTIFIER: "ISBN : 007054234X"
    assert_response :created

    body = response.parsed_body
    assert body["ok"]
    new_id = body["book"]["ID"]
    refute_nil new_id

    row = book(new_id)
    assert_equal "Real Analysis", row["TITLE"]
    assert_equal "Alex Lu",       row["OWNER"]
    assert_equal "Rudin",         row["CREATOR"]

    a = audit_rows.first
    assert_equal new_id,          a["BOOK_ID"]
    assert_equal "ADDED",         a["FIELD"]
    assert_nil   a["OLD_VALUE"]
    assert_equal "Real Analysis", a["NEW_VALUE"]
    assert_equal @user.full_name, a["EDITOR"]
    refute_nil   a["IP"]
  end

  test "add book blank fields become null" do
    post_json "/api/book", TITLE: "T", OWNER: "O", SERIES: "  "
    assert_response :created
    new_id = response.parsed_body["book"]["ID"]
    assert_nil book(new_id)["SERIES"]
  end

  # ── Remove a book ─────────────────────────────────────────────────────────

  test "remove book without login is rejected" do
    delete_json "/api/book/1", {}, {}
    assert_response :unauthorized
    refute_nil book(1) # still present
    assert_equal 0, audit_rows.length
  end

  test "remove nonexistent book returns 404" do
    delete_json "/api/book/9999", {}
    assert_response :not_found
  end

  test "remove book deletes and audits" do
    delete_json "/api/book/1", {}
    assert_response :success
    assert_nil book(1) # gone

    a = audit_rows.first
    assert_equal 1,                   a["BOOK_ID"]
    assert_equal "REMOVED",           a["FIELD"]
    assert_equal "Quantum Mechanics", a["OLD_VALUE"] # title preserved in the log
    assert_nil   a["NEW_VALUE"]
    assert_equal @user.full_name,     a["EDITOR"]
    refute_nil   a["IP"]
  end

  test "removed book still appears in audit log" do
    delete_json "/api/book/1", {}
    get "/api/audit"
    rows = response.parsed_body
    entry = rows.find { |r| r["FIELD"] == "REMOVED" }
    refute_nil entry
    assert_nil entry["BOOK_TITLE"] # LEFT JOIN: row is gone
    assert_equal "Quantum Mechanics", entry["OLD_VALUE"] # but title survives here
  end

  # ── Identifier lookup ──────────────────────────────────────────────────────

  test "lookup requires an identifier param" do
    get "/api/lookup"
    assert_response :bad_request
  end

  test "lookup returns 404 when genuinely not found" do
    get "/api/lookup", params: { isbn: "9999999999" } # DISABLE_OPENLIBRARY='1' -> :not_found -> 404
    assert_response :not_found
  end

  test "lookup returns 503 on transient error" do
    ENV["DISABLE_OPENLIBRARY"] = "error"
    get "/api/lookup", params: { isbn: "9781470418847" } # a valid ISBN, but service errors
    assert_response :service_unavailable
    assert_match(/temporarily unavailable/i, response.parsed_body["error"])
  ensure
    ENV["DISABLE_OPENLIBRARY"] = "1"
  end

  # ── Bulk import endpoint ──────────────────────────────────────────────────

  test "bulk requires login" do
    post_json "/api/books/bulk", { csv: "Owner,Title,Identifier\nA,B,ISBN : 1\n" }, {}
    assert_response :unauthorized
  end

  test "bulk missing headers returns 400" do
    post_json "/api/books/bulk", csv: "Owner,Title\nA,B\n"
    assert_response :bad_request
    assert_match(/Identifier/i, response.parsed_body["error"])
  end

  test "bulk imports valid rows and audits" do
    csv = <<~CSV
      Owner,Title,Creator,Identifier
      Alex Lu,Algebra,Lang,ISBN : 038795385X
      Sanjay,Analysis,Rudin,LC : 76087199
    CSV
    post_json "/api/books/bulk", csv: csv
    assert_response :success
    body = response.parsed_body
    assert_equal 2, body["added"].length
    assert_empty body["skipped"]

    titles = Book.where(TITLE: [ "Algebra", "Analysis" ]).pluck(:TITLE)
    assert_equal %w[Algebra Analysis], titles.sort
    added_audits = audit_rows.select { |a| a["FIELD"] == "ADDED" }
    assert_equal 2, added_audits.length
    assert(added_audits.all? { |a| a["EDITOR"] == @user.full_name && !a["IP"].nil? })
  end

  test "bulk skips rows missing required fields" do
    csv = <<~CSV
      Owner,Title,Identifier
      ,No Owner,ISBN : 1
      Alex,Good Book,ISBN : 2
    CSV
    post_json "/api/books/bulk", csv: csv
    body = response.parsed_body
    assert_equal 1, body["added"].length
    assert_equal 1, body["skipped"].length
    assert_equal 2, body["skipped"][0]["line"]
    assert_match(/Owner/i, body["skipped"][0]["reason"])
  end

  test "bulk skips rows without isbn or lc when offline, flagging them as retryable" do
    csv = <<~CSV
      Owner,Title,Identifier
      Alex,No Identifier Book,OCLC : (OCoLC)123
    CSV
    post_json "/api/books/bulk", csv: csv
    body = response.parsed_body
    assert_empty body["added"]
    assert_equal 1, body["skipped"].length
    assert_match(/ISBN or LC/i, body["skipped"][0]["reason"])
    assert body["skipped"][0]["missing_identifier"]
  end

  test "bulk adds rows without isbn or lc when force_no_identifier is set" do
    csv = <<~CSV
      Owner,Title,Identifier
      Alex,No Identifier Book,OCLC : (OCoLC)123
    CSV
    post_json "/api/books/bulk", csv: csv, force_no_identifier: true
    body = response.parsed_body
    assert_equal 1, body["added"].length
    assert_empty body["skipped"]

    row = Book.find_by(TITLE: "No Identifier Book")
    refute_nil row
    assert_equal "OCLC : (OCoLC)123", row["IDENTIFIER"]
  end

  test "bulk with force_no_identifier still skips rows missing required fields" do
    csv = <<~CSV
      Owner,Title,Identifier
      ,No Owner,
    CSV
    post_json "/api/books/bulk", csv: csv, force_no_identifier: true
    body = response.parsed_body
    assert_empty body["added"]
    assert_equal 1, body["skipped"].length
    assert_match(/Owner/i, body["skipped"][0]["reason"])
  end

  # ── Thumbnail (no network paths only) ─────────────────────────────────────

  test "thumbnail 404 when no identifiers" do
    get "/api/book/2/thumbnail" # book 2 has an empty IDENTIFIER
    assert_response :not_found
  end

  test "thumbnail serves cached file" do
    FileUtils.mkdir_p(ENV["LIBRARY_IMG_DIR"])
    cached = File.join(ENV["LIBRARY_IMG_DIR"], "1.jpg")
    File.binwrite(cached, "fakejpegbytes")
    get "/api/book/1/thumbnail"
    assert_response :success
    assert_equal "fakejpegbytes", response.body
  ensure
    File.delete(cached) if cached && File.exist?(cached)
  end
end
