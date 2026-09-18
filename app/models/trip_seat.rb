class TripSeat < ApplicationRecord
  include AASM

  belongs_to :trip
  belongs_to :hold, optional: true
  # A seat accumulates tickets over time: cancel a booking and the seat goes back
  # on sale, keeping the old ticket as history. So the base association is
  # has_many, and the live one is a scoped has_one.
  has_many :tickets, dependent: :restrict_with_error
  has_many :bookings, through: :tickets

  # The ticket that currently owns this seat. At most one can exist, because a
  # seat is 'booked' for exactly one confirmed booking at a time.
  has_one :current_ticket, -> { joins(:booking).merge(Booking.confirmed) },
          class_name: "Ticket", inverse_of: :trip_seat, dependent: nil
  has_one :current_booking, through: :current_ticket, source: :booking

  # Everything else: cancelled, and later rescheduled. Deliberately not named
  # cancelled_tickets -- a rescheduled booking's ticket is neither confirmed nor
  # cancelled, and would fall through a two-way split.
  has_many :past_tickets, -> { joins(:booking).where.not(bookings: { status: "confirmed" }) },
           class_name: "Ticket", inverse_of: :trip_seat, dependent: nil

  validates :seat_number, presence: true,
                          uniqueness: { scope: :trip_id, case_sensitive: false }
  validates :price_paise, numericality: { greater_than_or_equal_to: 0 }

  scope :available, -> { where(status: "available") }

  # One grouped query for a whole page of results. Calling trip.available_seats_count
  # per row would be one query per trip, which is the classic N+1 on the hottest
  # page in the app.
  def self.available_counts_by_trip(trip_ids)
    available.where(trip_id: trip_ids).group(:trip_id).count
  end
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

    # Rescheduling books a seat without a hold: the pick and the commit are one
    # locked transaction, so the five-minute reservation buys nothing. Kept as a
    # separate event rather than widening `confirm`, so the ordinary flow still
    # cannot book a seat nobody held.
    event :book do
      transitions from: :available, to: :booked
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
