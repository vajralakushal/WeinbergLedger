require "test_helper"

class ApiAuthTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  # auth_headers is a trailing positional (not keyword) argument on purpose —
  # Ruby 3 won't let a call site pass an implicit "key: value, ..." payload
  # hash once the method also declares keyword params.
  def post_json(path, payload, auth_headers = {})
    post path, params: payload.to_json, headers: JSON_HEADERS.merge(auth_headers)
  end

  def patch_json(path, payload, auth_headers = {})
    patch path, params: payload.to_json, headers: JSON_HEADERS.merge(auth_headers)
  end

  # ── Registration ───────────────────────────────────────────────────────────

  test "registration with correct quiz answer creates a pending user with a 4-digit id" do
    post_json "/api/registrations", first_name: "Ada", last_name: "Lovelace",
                                     username: "ada", password: "s3cret123", light_speed: "1"
    assert_response :created
    body = response.parsed_body
    assert body["ok"]
    assert_equal User::PENDING, body["approval_status"]
    assert_includes 1..9999, body["user_id"]

    user = User.find_by(user_id: body["user_id"])
    refute_nil user
    assert_equal "ada", user.username
    assert user.authenticate("s3cret123")
  end

  test "registration with wrong quiz answer is denied and creates nothing" do
    before = User.count
    post_json "/api/registrations", first_name: "Bot", last_name: "Script",
                                     username: "bot1", password: "whatever", light_speed: "42"
    assert_response :forbidden
    body = response.parsed_body
    assert body["denied"]
    assert_match(/denied/i, body["error"])
    assert_equal before, User.count
  end

  test "registration requires the core fields" do
    post_json "/api/registrations", username: "onlyusername", light_speed: "1"
    assert_response :unprocessable_entity
  end

  test "registration rejects a duplicate username" do
    create_user!(username: "taken")
    post_json "/api/registrations", first_name: "A", last_name: "B",
                                     username: "taken", password: "password123", light_speed: "1"
    assert_response :unprocessable_entity
    assert_match(/username/i, response.parsed_body["error"])
  end

  test "registration sweeps stale pending and denied users, reclaiming their ids" do
    stale = create_user!(approval_status: User::PENDING, created_at: 25.hours.ago)
    denied = create_user!(approval_status: User::DENIED)
    stale_id  = stale.user_id
    denied_id = denied.user_id

    post_json "/api/registrations", first_name: "Fresh", last_name: "One",
                                     username: "freshone", password: "password123", light_speed: "1"
    assert_response :created

    refute User.exists?(user_id: stale_id)
    refute User.exists?(user_id: denied_id)
  end

  # ── Login / logout ─────────────────────────────────────────────────────────

  test "login rejects wrong password" do
    create_user!(username: "loginuser", password: "correcthorse")
    post_json "/api/sessions", username: "loginuser", password: "wrong"
    assert_response :unauthorized
  end

  test "login rejects an unapproved account" do
    create_user!(username: "pendinguser", password: "password123", approval_status: User::PENDING)
    post_json "/api/sessions", username: "pendinguser", password: "password123"
    assert_response :forbidden
  end

  test "login succeeds and returns a usable token" do
    create_user!(username: "gooduser", password: "password123")
    post_json "/api/sessions", username: "gooduser", password: "password123"
    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    refute_nil body["token"]
    assert_equal "gooduser", body["user"]["username"]

    get "/api/me", headers: JSON_HEADERS.merge("Authorization" => "Bearer #{body['token']}")
    assert_response :success
    assert_equal "gooduser", response.parsed_body["username"]
  end

  test "logout revokes the token" do
    user = create_user!(username: "logoutuser", password: "password123")
    auth = auth_headers_for(user)

    delete "/api/sessions", headers: JSON_HEADERS.merge(auth)
    assert_response :success

    get "/api/me", headers: JSON_HEADERS.merge(auth)
    assert_response :unauthorized
  end

  # ── /me ──────────────────────────────────────────────────────────────────

  test "me requires login" do
    get "/api/me"
    assert_response :unauthorized
  end

  test "change password requires the correct current password" do
    user = create_user!(password: "original123")
    auth = auth_headers_for(user)
    patch_json "/api/me/password", { old_password: "wrong", new_password: "newpass123",
                                      new_password_confirmation: "newpass123" }, auth
    assert_response :unprocessable_entity
  end

  test "change password requires matching confirmation" do
    user = create_user!(password: "original123")
    auth = auth_headers_for(user)
    patch_json "/api/me/password", { old_password: "original123", new_password: "newpass123",
                                      new_password_confirmation: "different" }, auth
    assert_response :unprocessable_entity
  end

  test "change password succeeds and clears must_change_password" do
    user = create_user!(password: "original123", must_change_password: true)
    auth = auth_headers_for(user)
    patch_json "/api/me/password", { old_password: "original123", new_password: "newpass123",
                                      new_password_confirmation: "newpass123" }, auth
    assert_response :success

    refute user.reload.must_change_password
    assert user.authenticate("newpass123")
  end
end
