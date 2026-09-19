require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "creating a session generates a raw token available only in memory" do
    user = create_user!
    session = user.sessions.create!
    refute_nil session.raw_token
    refute_equal session.raw_token, session.token_digest
    assert_equal Session.digest(session.raw_token), session.token_digest
  end

  test "authenticate finds the session for a valid token" do
    user = create_user!
    session = user.sessions.create!
    found = Session.authenticate(session.raw_token)
    assert_equal session.id, found&.id
  end

  test "authenticate returns nil for a bogus or blank token" do
    assert_nil Session.authenticate("not-a-real-token")
    assert_nil Session.authenticate("")
    assert_nil Session.authenticate(nil)
  end

  test "authenticate returns nil for an expired session" do
    user = create_user!
    session = user.sessions.create!(expires_at: 1.minute.ago)
    assert session.expired?
    assert_nil Session.authenticate(session.raw_token)
  end
end
