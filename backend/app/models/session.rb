require "securerandom"
require "digest"

class Session < ApplicationRecord
  self.table_name = "SESSIONS"

  belongs_to :user, foreign_key: "user_id", primary_key: "user_id", inverse_of: :sessions

  TOKEN_TTL = 30.days

  before_validation :assign_token, on: :create

  # The raw bearer token — only ever available in memory right after
  # creation. Only its digest is persisted, so it can't be recovered later.
  attr_reader :raw_token

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    session = find_by(token_digest: digest(raw_token))
    return nil if session.nil? || session.expired?

    session
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  private

  def assign_token
    return if token_digest.present?

    @raw_token = SecureRandom.hex(32)
    self.token_digest = self.class.digest(@raw_token)
    self.expires_at ||= TOKEN_TTL.from_now
  end
end
