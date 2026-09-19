ENV["RAILS_ENV"] ||= "test"

require "tmpdir"
require "minitest/mock" # Object#stub, used to stub OpenLibraryService.http_get in tests
# Point cover-image fetches at a throwaway dir and keep OpenLibrary calls
# offline by default, so tests never touch the real img/ directory or the
# network — mirrors the old app_test.rb's ENV setup, just set before boot.
ENV["LIBRARY_IMG_DIR"]     ||= Dir.mktmpdir("weinberg-test-img")
ENV["DISABLE_OPENLIBRARY"] ||= "1"

require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Fully reset LIBRARY/AUDIT_LOG to a two-book seed before every test
    # (order-independent, since add/remove tests insert and delete rows).
    # Also wrapped in a per-test transaction (Rails default) that rolls back
    # automatically, so this never touches the real library.db.
    def seed_library!
      AuditLog.delete_all
      Book.delete_all
      Book.create!(ID: 1, OWNER: "Alex Lu", TITLE: "Quantum Mechanics",
                    CREATOR: "Griffiths", IDENTIFIER: "ISBN : 9780131118928")
      Book.create!(ID: 2, OWNER: "Sanjay Mathai", TITLE: "Topology",
                    CREATOR: "Munkres", IDENTIFIER: "")
    end

    # Builds an approved user ready to log in, matching the shape the
    # RegistrationsController produces once approved. Give a unique
    # username per call (tests may create several).
    def create_user!(overrides = {})
      seq = (@user_seq ||= 0) + 1
      @user_seq = seq
      User.create!({
        first_name: "Test", last_name: "User#{seq}", username: "testuser#{seq}",
        password: "password123", approval_status: User::APPROVED
      }.merge(overrides))
    end

    # A real Session row (not a stubbed token), so controller-level
    # Session.authenticate lookups behave exactly as in production.
    def auth_headers_for(user)
      { "Authorization" => "Bearer #{user.sessions.create!.raw_token}" }
    end
  end
end
