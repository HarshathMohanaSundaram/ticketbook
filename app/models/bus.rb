class Bus < ApplicationRecord
  BUS_TYPES = %w[ac non_ac].freeze
  BERTH_TYPES = %w[sleeper seater].freeze
  AMENITY_CODES = %w[wifi charging_point blanket water_bottle reading_light cctv track_my_bus].freeze

  belongs_to :operator
  has_many :trips, dependent: :restrict_with_error

  validates :registration_number, presence: true, uniqueness: true
  validates :bus_type, inclusion: { in: BUS_TYPES }
  validates :berth_type, inclusion: { in: BERTH_TYPES }
  validates :seats_total, numericality: { greater_than: 0 }
  validate :amenity_codes_are_known

  def ac? = bus_type == "ac"
  def sleeper? = berth_type == "sleeper"

  def label
    "#{ac? ? 'AC' : 'Non-AC'} #{berth_type.humanize}"
  end

  private

  def amenity_codes_are_known
    unknown = amenity_codes.to_a - AMENITY_CODES
    errors.add(:amenity_codes, "contains unknown codes: #{unknown.join(', ')}") if unknown.any?
  end
end
