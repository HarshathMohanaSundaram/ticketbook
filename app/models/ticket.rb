class Ticket < ApplicationRecord
  belongs_to :booking
  belongs_to :trip_seat

  validates :passenger_name, presence: true
  validates :price_paise, numericality: { greater_than_or_equal_to: 0 }
  validates :trip_seat_id, uniqueness: { scope: :booking_id }
  validates :passenger_age, numericality: { greater_than: 0, less_than: 120 }, allow_nil: true

  delegate :seat_number, :berth_type, to: :trip_seat
end
