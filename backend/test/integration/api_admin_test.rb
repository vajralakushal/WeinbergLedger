require "test_helper"

class ApiAdminTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  setup do
    seed_library!
    @admin = create_user!(admin_status: true)
    @admin_auth = auth_headers_for(@admin)
    @user  = create_user!
    @user_auth = auth_headers_for(@user)
  end

  def patch_json(path, payload, headers:)
    patch path, params: payload.to_json, headers: JSON_HEADERS.merge(headers)
  end

  def delete_json(path, payload, headers:)
    delete path, params: payload.to_json, headers: JSON_HEADERS.merge(headers)
  end

  test "admin routes require login" do
    get "/api/admin/users"
    assert_response :unauthorized
  end

  test "admin routes reject non-admin users" do
    get "/api/admin/users", headers: @user_auth
    assert_response :forbidden
  end

  test "index lists users and can filter by approval_status" do
    pending_user = create_user!(approval_status: User::PENDING)

    get "/api/admin/users", headers: @admin_auth
    assert_response :success
    ids = response.parsed_body.map { |u| u["user_id"] }
    assert_includes ids, pending_user.user_id
    assert_includes ids, @user.user_id

    get "/api/admin/users", params: { approval_status: User::PENDING }, headers: @admin_auth
    body = response.parsed_body
    assert body.all? { |u| u["approval_status"] == User::PENDING }
    assert_includes body.map { |u| u["user_id"] }, pending_user.user_id
  end

  test "index sweeps stale pending and denied users" do
    stale  = create_user!(approval_status: User::PENDING, created_at: 25.hours.ago)
    denied = create_user!(approval_status: User::DENIED)

    get "/api/admin/users", headers: @admin_auth
    assert_response :success

    refute User.exists?(user_id: stale.user_id)
    refute User.exists?(user_id: denied.user_id)
  end

  test "approve flips a pending user to approved" do
    pending_user = create_user!(approval_status: User::PENDING)
    patch "/api/admin/users/#{pending_user.user_id}/approve", headers: @admin_auth
    assert_response :success
    assert_equal User::APPROVED, pending_user.reload.approval_status
  end

  test "destroy removes the user" do
    delete "/api/admin/users/#{@user.user_id}", headers: @admin_auth
    assert_response :success
    refute User.exists?(user_id: @user.user_id)
  end

  test "destroy with reassign_books_to moves owner and borrower text first" do
    Book.create!(ID: 500, OWNER: @user.full_name, BORROWER: @user.full_name, TITLE: "Orphan Book")

    delete_json "/api/admin/users/#{@user.user_id}", { reassign_books_to: "New Owner" }, headers: @admin_auth
    assert_response :success
    refute User.exists?(user_id: @user.user_id)

    book = Book.find_by(ID: 500)
    assert_equal "New Owner", book["OWNER"]
    assert_equal "New Owner", book["BORROWER"]
  end

  test "reset_password sets a working temporary password and forces a change" do
    patch "/api/admin/users/#{@user.user_id}/reset_password", headers: @admin_auth
    assert_response :success
    body = response.parsed_body
    refute_nil body["temp_password"]

    @user.reload
    assert @user.authenticate(body["temp_password"])
    assert @user.must_change_password
  end

  test "make_admin flips admin_status" do
    patch "/api/admin/users/#{@user.user_id}/make_admin", headers: @admin_auth
    assert_response :success
    assert @user.reload.admin_status
  end

  test "actions on a nonexistent user return 404" do
    patch "/api/admin/users/999999/approve", headers: @admin_auth
    assert_response :not_found
  end
end
