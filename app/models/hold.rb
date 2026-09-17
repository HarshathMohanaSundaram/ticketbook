class Hold < ApplicationRecord
  HOLD_WINDOW = 5.minutes
  MAX_SEATS = 6

  belongs_to :user
  belongs_to :trip
  has_many :trip_seats, dependent: :nullify   # the seats currently pointing at this hold
  has_one :booking, dependent: :nullify

  enum :status, { active: "active", converted: "converted", released: "released", expired: "expired" },
       validate: true

  validates :expires_at, presence: true

  scope :live, -> { active.where(expires_at: Time.current..) }
  # What the sweeper looks for: still marked active, but the window has passed.
  scope :expirable, -> { active.where(expires_at: ..Time.current) }

  def live?(at = Time.current) = active? && expires_at > at

  def seconds_remaining(at = Time.current) = [ (expires_at - at).to_i, 0 ].max
end
