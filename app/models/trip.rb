class Trip < ApplicationRecord
  TZ = "Asia/Kolkata".freeze
  # Nothing may be held this close to departure -- the hold would outlive the bus.
  BOOKING_CUTOFF = 30.minutes

  belongs_to :operator
  belongs_to :bus
  belongs_to :origin_city, class_name: "City"
  belongs_to :destination_city, class_name: "City"
  # Nullable: a trip can be published before the roster is assigned. A relief
  # driver is required by law on long runs and pointless on short ones.
  belongs_to :driver, optional: true
  belongs_to :relief_driver, class_name: "Driver", optional: true

  has_many :trip_seats, dependent: :destroy
  has_many :trip_stops, dependent: :destroy
  # STI scopes these by type on its own -- no where clause needed.
  has_many :boarding_stops, -> { ordered }, class_name: "BoardingStop", inverse_of: :trip, dependent: nil
  has_many :dropping_stops, -> { ordered }, class_name: "DroppingStop", inverse_of: :trip, dependent: nil
  # The places themselves, when you need the list without the timings.
  has_many :stop_points, through: :trip_stops
  has_many :holds, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  enum :status, { scheduled: "scheduled", departed: "departed", cancelled: "cancelled" }, validate: true

  validates :departs_at, :arrives_at, :base_fare_paise, presence: true
  validate :arrival_after_departure
  validate :cities_differ
  validate :drivers_work_for_the_operator

  # Reading a value and filtering on it are different problems: delegate serves
  # the views, joins serve the WHERE clause.
  delegate :bus_type, :berth_type, :amenity_codes, :label, to: :bus, prefix: false
  delegate :name, :rating, to: :operator, prefix: true

  scope :bookable, -> { scheduled.where(departs_at: BOOKING_CUTOFF.from_now..) }
  scope :between_cities, ->(origin_id, destination_id) {
    where(origin_city_id: origin_id, destination_city_id: destination_id)
  }
  # Half-open range in IST resolved to UTC by Rails: reads the composite index
  # directly, with no function wrapped around the column.
  scope :on_date, ->(date) { where(departs_at: date.in_time_zone(TZ).all_day) }
  scope :priced_between, ->(min_paise, max_paise) {
    scope = all
    scope = scope.where(base_fare_paise: min_paise..) if min_paise.present?
    scope = scope.where(base_fare_paise: ..max_paise) if max_paise.present?
    scope
  }
  scope :rated_at_least, ->(rating) {
    rating.blank? ? all : joins(:operator).where(operators: { rating: rating.. })
  }
  scope :of_bus_type, ->(type) { type.blank? ? all : joins(:bus).where(buses: { bus_type: type }) }
  scope :of_berth_type, ->(type) { type.blank? ? all : joins(:bus).where(buses: { berth_type: type }) }
  scope :with_amenities, ->(codes) {
    codes = Array(codes).compact_blank
    codes.blank? ? all : joins(:bus).where("buses.amenity_codes @> ARRAY[?]::varchar[]", codes)
  }

  # The service date a passenger means when they say "the 19th". Derived in Ruby
  # because a stored column would have to be kept in step with departs_at, and a
  # generated one is impossible: Postgres requires IMMUTABLE, and a timezone
  # conversion is only STABLE.
  def service_date = departs_at.in_time_zone(TZ).to_date

  def bookable? = scheduled? && departs_at > BOOKING_CUTOFF.from_now

  def duration_minutes = ((arrives_at - departs_at) / 60).to_i

  # Both drivers on the run, in order, skipping the empty slots.
  def crew = [ driver, relief_driver ].compact

  # Always counted off trip_seats: there is no availability counter to go stale.
  def available_seats_count = trip_seats.where(status: "available").count

  private

  def arrival_after_departure
    return if departs_at.blank? || arrives_at.blank? || arrives_at > departs_at

    errors.add(:arrives_at, "must be after departure")
  end

  # Same class of bug as a stop from another trip: the FK only proves the driver
  # exists, not that they work for the operator running this bus.
  def drivers_work_for_the_operator
    { driver: driver, relief_driver: relief_driver }.each do |attribute, person|
      next if person.nil? || person.operator_id == operator_id

      errors.add(attribute, "does not work for #{operator&.name || 'this operator'}")
    end
  end

  def cities_differ
    return if origin_city_id.blank? || origin_city_id != destination_city_id

    errors.add(:destination_city_id, "must differ from the origin city")
  end
end
