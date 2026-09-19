class User < ApplicationRecord
  self.table_name = "USERS"
  self.primary_key = "user_id"

  PENDING  = "PENDING"
  APPROVED = "APPROVED"
  DENIED   = "DENIED"
  APPROVAL_STATUSES = [ PENDING, APPROVED, DENIED ].freeze

  # How long a registration may sit PENDING before it's swept away, reclaiming
  # its 4-digit ID — also applies immediately to DENIED rows (see sweep_stale!).
  PENDING_EXPIRY = 24.hours

  # How many random 4-digit IDs to try before giving up (collision retry).
  MAX_ID_ATTEMPTS = 50

  has_secure_password
  has_many :sessions, foreign_key: "user_id", inverse_of: :user, dependent: :destroy

  before_validation :assign_user_id, on: :create
  before_validation :normalize_username

  validates :first_name, :last_name, :username, presence: true
  validates :username, uniqueness: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  def full_name
    "#{first_name} #{last_name}"
  end

  def approved?
    approval_status == APPROVED
  end

  # Deletes DENIED users outright, and PENDING users whose registration has
  # sat unreviewed past PENDING_EXPIRY — reclaims their 4-digit IDs.
  def self.sweep_stale!
    where(approval_status: DENIED).destroy_all
    where(approval_status: PENDING).where("created_at < ?", PENDING_EXPIRY.ago).destroy_all
  end

  private

  def assign_user_id
    return if user_id.present?

    MAX_ID_ATTEMPTS.times do
      candidate = rand(1..9999)
      next if self.class.exists?(user_id: candidate)

      self.user_id = candidate
      return
    end
    errors.add(:base, "No user IDs are available right now — please try again later.")
  end

  def normalize_username
    self.username = username.to_s.strip
  end
end
