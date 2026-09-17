class Booking < ApplicationRecord
  # Cancellation is allowed only up to an hour before departure, and the refund
  # is the fare less a flat fifty rupees.
  CANCELLATION_CUTOFF = 1.hour
  CANCELLATION_FEE_PAISE = 5_000

  belongs_to :user
  belongs_to :trip
  belongs_to :hold, optional: true
  # Typed to the STI subclasses: handing `dropping_stop` a BoardingStop raises
  # AssociationTypeMismatch, so a ticket cannot print the pickup time as the
  # drop time. The FK still only guarantees the row exists -- that it belongs to
  # *this* trip is what the validation below is for.
  belongs_to :boarding_stop, class_name: "BoardingStop", optional: true
  belongs_to :dropping_stop, class_name: "DroppingStop", optional: true
  belongs_to :rescheduled_from, class_name: "Booking", optional: true

  has_many :tickets, dependent: :destroy
  has_many :trip_seats, through: :tickets
  has_one :rescheduled_to, class_name: "Booking", foreign_key: :rescheduled_from_id,
          inverse_of: :rescheduled_from, dependent: :nullify

  enum :status, { confirmed: "confirmed", cancelled: "cancelled", rescheduled: "rescheduled" },
       validate: true

  validates :pnr, presence: true, uniqueness: true
  validates :total_paise, numericality: { greater_than_or_equal_to: 0 }
  validate :stops_belong_to_this_trip

  scope :recent_first, -> { order(created_at: :desc) }
  scope :upcoming, -> { confirmed.where(departs_at: Time.current..) }

  # Addressed by PNR rather than id, so /bookings/4 is not a thing a curious
  # reviewer can try.
  def to_param = pnr

  # Eight characters of Crockford-ish base32: no vowels, so it cannot spell
  # anything, and no 0/O or 1/I to misread over the phone.
  PNR_ALPHABET = "23456789BCDFGHJKLMNPQRSTVWXYZ".chars.freeze

  def self.generate_pnr = Array.new(8) { PNR_ALPHABET.sample }.join

  # Cancellable only while confirmed and still at least an hour from departure.
  # Takes the clock so a service can check and record against the same instant,
  # and so specs can stand at the boundary without waiting for it.
  def cancellable?(at = Time.current)
    confirmed? && (departs_at - at) >= CANCELLATION_CUTOFF
  end

  # What a cancellation *would* refund. The stored refund_paise column records
  # what one actually did.
  def projected_refund_paise = [ total_paise - CANCELLATION_FEE_PAISE, 0 ].max

  def seat_numbers = trip_seats.map(&:seat_number).sort

  private

  # A trip_stop from another departure would print a plausible-looking place and
  # a completely wrong time, so refuse it.
  def stops_belong_to_this_trip
    { boarding_stop: boarding_stop, dropping_stop: dropping_stop }.each do |attribute, stop|
      next if stop.nil? || stop.trip_id == trip_id

      errors.add(attribute, "is not a stop on this trip")
    end
  end
end
