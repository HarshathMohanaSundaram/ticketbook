class TripSeat < ApplicationRecord
  include AASM

  belongs_to :trip
  belongs_to :hold, optional: true
  has_one :ticket, dependent: :restrict_with_error
  has_one :booking, through: :ticket

  validates :seat_number, presence: true,
                          uniqueness: { scope: :trip_id, case_sensitive: false }
  validates :price_paise, numericality: { greater_than_or_equal_to: 0 }

  scope :available, -> { where(status: "available") }
  scope :for_hold, ->(hold) { where(hold_id: hold) }
  scope :numbered, -> { order(:seat_number) }

  # The lifecycle in one readable block. Every transition runs inside a service's
  # transaction, after that row has been locked -- the state machine refuses
  # illegal moves, the lock decides who gets to move first.
  aasm column: :status, whiny_persistence: true do
    state :available, initial: true
    state :held
    state :booked
    state :blocked

    event :place_hold do
      transitions from: :available, to: :held
    end

    event :confirm do
      transitions from: :held, to: :booked
    end

    event :release do
      transitions from: %i[held booked], to: :available
    end

    event :block do
      transitions from: :available, to: :blocked
    end
  end

  # A held seat whose window has passed is free. Checked inside the row lock, so
  # the answer cannot change between the check and the write -- and so a late or
  # dead background job can never leave a seat permanently unsellable.
  def stale_hold?(at = Time.current)
    held? && hold_expires_at.present? && hold_expires_at <= at
  end

  def claimable?(at = Time.current) = available? || stale_hold?(at)

  def clear_hold!
    update!(hold_id: nil, hold_expires_at: nil)
  end
end
